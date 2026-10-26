# Politique de tags — Shop SAS

Le tag est un pointeur. Le digest (`sha256:…`) est l'image. En production on déploie un digest. Le tag sert à nommer une release, pas à la figer.

## Tags autorisés

| Tag | Exemple | Mutable | Rôle |
| --- | --- | --- | --- |
| semver | `1.4.2`, `v1.4.2` | non | Release. Une fois poussé, on ne le réécrit pas. |
| préfixe de release | `1.4` | oui | Pointe vers le dernier patch de la mineure. Jamais déployé seul. |
| commit | `sha-a1b2c3d` | non | Build de CI, une fois. |
| build flottant | `build-1042`, `nightly` | oui | Le script `retention.sh` n'en garde que les N plus récents. |

`retention.sh` reconnaît le semver (`1.4.2`, `v1.2.3`, suffixe `+build`). Il ne supprime jamais ces tags. Les autres sont triés par date de création de l'image, et seuls les N plus récents restent.

## Tags interdits en production

`latest` est interdit. Il est réécrit à chaque push, sans historique dans le manifeste que le cluster a tiré. L'incident du vendredi (une image `latest` remplacée) vient de là : le déploiement ne disait pas quelle image tournait, et un rollback retélécharge la même étiquette, donc la nouvelle image.

Même règle pour `dev`, `stable`, `prod` s'ils sont réécrits. Un environnement peut avoir un tag de canal, mais le manifeste Kubernetes ou le compose de prod épingle le digest.

## Immuabilité

Avec le registre `registry:2` et `htpasswd`, rien n'empêche de refaire `docker push` sur `1.4.2`. L'immuabilité est une règle d'équipe, pas un contrôle technique. Harbor, Nexus, Artifactory, ECR, ACR et GAR peuvent refuser l'écrasement d'un tag. Ici, la signature cosign rattrape l'écart : elle est attachée au digest. Réécrire le tag casse `cosign verify` tant qu'on n'a pas re-signé.

## Digest dans Compose

`skopeo copy --all` de `shopapi:1.4.2` vers `shopapi:stable` a conservé le digest `sha256:caa713181d192aada892750384ba54bb5343fe1aec8fb3422e537c2aa7ea935a`. Sans `--all`, skopeo n'a copié qu'un manifeste et le digest a changé (`sha256:4043c77e…` pour le tag `1.4`).

```yaml
services:
  api:
    image: registry.local:5000/shopapi@sha256:caa713181d192aada892750384ba54bb5343fe1aec8fb3422e537c2aa7ea935a
```

Le tag peut rester en commentaire pour les humains. Le runtime tire le digest, qui ne bouge pas si quelqu'un repousse `1.4.2`.
