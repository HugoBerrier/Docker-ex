# Rapport TP03 — registre privé et supply chain

Registre : `starter/registry/compose.yml`, config dans `config.yml` (pas une quinzaine de variables).
Porte de release : `starter/release-gate.sh`.
Rétention : `retention.sh`. Politique de tags : `TAGGING.md`.

Comptes : `ci` / `ci-push-2024`, `dev` / `dev-pull-2024`. Les hash bcrypt sont dans `starter/registry/auth/htpasswd`.

Sur ce Mac, le port 5000 est pris par AirPlay Receiver (`ControlCenter`). Le `compose.yml` livré publie bien **5000**, comme le sujet. Les mesures ci-dessous passent par `127.0.0.1:5500` (`compose.override.yml`, non versionné). Pas de sudo pour écrire `/etc/hosts` : le certificat a le SAN `registry.local` et `127.0.0.1`, et le client Docker fait confiance à la CA via `~/.docker/certs.d/`. `install-client.sh` copie aussi la CA dans `/etc/docker/certs.d` et ajoute `registry.local` quand sudo est disponible.

## 1. Registre

`gen-certs.sh` crée une CA interne et un certificat serveur. Le registre sert en HTTPS, auth htpasswd, volume nommé, `storage.delete.enabled: true`, healthcheck (le `GET /v2/` sans auth répond 401, c'est le signal que le serveur est debout). UI : [http://localhost:8080](http://localhost:8080) (`joxit/docker-registry-ui`), le proxy nginx atteint le registre. Mirror Hub sur le port 5001.

```text
curl sans auth                         401
curl -u dev:dev-pull-2024 …/_catalog   {"repositories":[]}
curl -u dev:wrong                      401
docker login 127.0.0.1:5500 -u ci      Login Succeeded
UI /v2/_catalog avec le compte dev     200
```

Push de `shopapi:1.4.2` : digest `sha256:caa713181d192aada892750384ba54bb5343fe1aec8fb3422e537c2aa7ea935a`.

`htpasswd` ne suffit pas en entreprise. Les deux comptes ont les mêmes droits : `dev` peut pousser, `ci` peut tout supprimer. Il n'y a pas de RBAC, pas de quota, pas d'immuabilité de tag, pas de scan à la réception, pas de réplication. Harbor, Nexus, Artifactory, ECR, ACR et GAR ajoutent exactement ça. Harbor en plus signe et scanne dans le registre, et peut refuser un tag déjà publié.

Le mirror : `docker pull 127.0.0.1:5001/library/alpine:3.20` télécharge les blobs (la couche de 3,6 Mo est écrite une fois). Le second pull ne refait qu'un `HEAD` du manifeste, répondu en 290 ms par le cache. `~/.docker/daemon.json` contient `"registry-mirrors": ["http://localhost:5001"]`. Je n'ai pas redémarré Docker Desktop : les conteneurs des exercices 05 à 09 tournent encore. Le mirror ne s'applique aux `docker pull alpine` ordinaires qu'après ce redémarrage. S'il est down, le daemon retombe sur Docker Hub.

## 2. API

Même digest pour `demo:one` et `demo:two` : `sha256:caa713181d19…`.

```text
DELETE /v2/demo/manifests/sha256:caa713181d19…    202
GET    /v2/demo/manifests/one                     404
GET    /v2/demo/manifests/two                     404
tags/list                                         {"tags": null}
```

Le registre ne supprime pas un tag, il supprime un manifeste. Si deux tags pointent le même digest, un seul `DELETE` retire les deux. `retention.sh` ne supprime donc un digest que s'il n'est plus référencé par un tag qu'on garde.

`retention.sh 127.0.0.1:5500 shopapi 2`, après avoir poussé `build-1` … `build-4` (dates réelles, lues dans le config blob, en suivant le manifeste `linux` de l'index OCI) :

| Tag | Sort | Décision |
| --- | --- | --- |
| `1.4.2`, `1.0.0` | semver | gardés |
| `build-4`, `build-3` | les 2 plus récents | gardés |
| `build-1`, `build-2` | plus anciens | supprimés |

`registry garbage-collect` (registre arrêté, puis relancé) : 58 blobs encore référencés, 2 blobs éligibles, ceux des tags retirés. Le dry-run les liste avant de les effacer.

## 3. Tags

Le détail est dans `TAGGING.md`. `latest` est interdit en prod parce qu'il est réécrit : le déploiement ne dit pas quelle image tourne, et un rollback retélécharge le même nom.

`skopeo copy` sans `--all` a produit un autre digest pour le tag `1.4` (`sha256:4043c77e…`) : il n'a copié qu'un manifeste, pas l'index. `skopeo copy --all` de `1.4.2` vers `stable` a conservé `sha256:caa713181d19…`. C'est un retag sans `docker pull`.

## 4. SBOM, scan, signature

`syft` sur `shopapi:1.4.3` : **134 paquets** dans `sbom.json`.

`trivy image --scanners secret` :

- `shopapi:legacy` : secret AWS dans `/app/.env` (la clé ajoutée par le `COPY .` du Dockerfile d'origine).
- `shopapi:1.4.2` : rien.

`trivy image --severity HIGH,CRITICAL --ignore-unfixed` :

- `shopapi:1.4.2` : 4 HIGH corrigibles, `libcrypto3` / `libssl3` `3.5.6-r0` (CVE-2026-14456, CVE-2026-45447, correctif `3.5.7` / `3.5.8`).
- `shopapi:legacy` : 0 HIGH/CRITICAL corrigible dans cette base (les paquets Ubuntu signalés sont non corrigés, donc ignorés par `--ignore-unfixed`).
- `shopapi:1.4.3` : 0. C'est `1.4.2` plus `apk upgrade libcrypto3 libssl3` (`3.5.9-r0`) et le label de version passé à `1.4.3`.

Signature de `127.0.0.1:5500/shopapi:1.4.3`, clé cosign à mot de passe vide, `--tlog-upload=false` (registre local, pas de Rekor) :

```text
sha256-b97c1741ee05ca81abbaec3b8790f40069e5ea4e8465410afd452566c20d420c.sig
sha256-b97c1741ee05ca81abbaec3b8790f40069e5ea4e8465410afd452566c20d420c.att
```

Le `.sig` est la signature, le `.att` est l'attestation SPDX. Les deux tags portent le **digest** `sha256:b97c1741…`, pas le nom `1.4.3`.

J'ai ensuite poussé une autre image sous le tag `1.4.3`. `cosign verify` répond `no signatures found` (code 10). La signature ne suit pas le tag. En repoussant le digest d'origine, `verify` repasse : il retrouve `sha256:b97c1741…`.

## 5. Porte de release

`./starter/release-gate.sh shopapi:legacy` sort **1**, cinq refus :

- label `revision` absent
- label `source` absent
- processus root (`User` vide). Le label `version=22.04` est celui de l'image Ubuntu de base, il ne suffit pas.
- pas de `HEALTHCHECK`
- secret détecté

`shopapi:1.4.2` a les labels, l'utilisateur `1000` et le healthcheck, et aucun secret. La porte la **refuse** quand même : 4 CVE HIGH corrigibles. Le sujet demandait de l'accepter. Avec la base Alpine du TP01, ce n'est plus vrai : openssl a un correctif. La pousser serait contredire la règle « CVE corrigible = pas de release ».

`shopapi:1.4.3` passe. `--push 127.0.0.1:5500/shopapi:1.4.3` pousse, signe et atteste. `verified-run.sh` vérifie la signature puis lance le conteneur : `uid=1000(node)`.

Trivy et syft ne sont pas installés sur la machine. Le script les lance en conteneur (`aquasec/trivy:0.58.1`, `anchore/syft:v1.18.1`, `ghcr.io/sigstore/cosign/cosign:v2.4.1`).

## Bonus

**B1.** `trivy image --download-db-only` puis `trivy server` : une base de CVE partagée, les CI ne la retéléchargent pas chacune. Je ne l'ai pas laissé tourner.

**B2.** La signature keyless (Fulcio + Rekor) évite de stocker `cosign.key`. L'identité est le compte GitHub ou le workflow OIDC, et le journal Rekor est public. Inconvénient : il faut un accès à Fulcio au moment de signer, et la vérification dépend de ce journal. La clé du TP marche hors ligne (`--tlog-upload=false`), mais celui qui copie `cosign.key` signe à la place de l'équipe. Le mot de passe vide ne change rien à ce risque.

**B3.** `verified-run.sh` refuse `docker run` si `cosign verify` échoue. C'est ce qui a bloqué l'image `1.4.3` réécrite.

**B4.** `trivy sbom sbom.json` relit le SPDX sans l'image. Utile six mois plus tard, quand de nouvelles CVE sortent et que le registre a encore le fichier. Limite mesurée : syft n'a pas mis d'OS détectable dans ce SBOM, trivy ignore alors les paquets Alpine (`Ignore the OS package as no OS is detected`). Les CVE openssl ne réapparaissent pas par ce chemin. Pour ça, le scan d'image reste nécessaire, ou un SBOM qui déclare l'OS.
