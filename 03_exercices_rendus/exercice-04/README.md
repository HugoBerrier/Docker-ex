# Exercice Docker #4 — Rendu

Deux conteneurs communiquent via un réseau Docker et se joignent **par nom** (DNS interne).

| Élément | Nom |
|---------|-----|
| Réseau | `exercice04-net` |
| Image | `ubuntu-ping` (Ubuntu + `iputils-ping`) |
| Conteneurs | `exercice04-ping-a`, `exercice04-ping-b` |

## Commandes exécutées

```bash
# 1. Créer le réseau
docker network create exercice04-net

# 2. Conteneur temporaire + installation de ping
docker run --name exercice04-build -it ubuntu bash
# dans le conteneur :
apt-get update
apt-get install -y iputils-ping
exit

# 3. Sauvegarder l'image
docker commit exercice04-build ubuntu-ping

# 4. Deux conteneurs sur le même réseau
docker run -d --name exercice04-ping-a --network exercice04-net ubuntu-ping sleep infinity
docker run -d --name exercice04-ping-b --network exercice04-net ubuntu-ping sleep infinity

# 5. Tester la résolution DNS + communication
docker exec exercice04-ping-a ping -c 3 exercice04-ping-b
docker exec exercice04-ping-b ping -c 3 exercice04-ping-a
```

## Résultat des tests

```
# A → B : résolution exercice04-ping-b → 172.18.0.3, 0% packet loss
# B → A : résolution exercice04-ping-a → 172.18.0.2, 0% packet loss
```

## Archive de l'image

Fichier : `ubuntu-ping.tar` (~71 Mo)

```bash
docker load -i ubuntu-ping.tar
```

## Vérification rapide

```bash
docker network ls | grep exercice04
docker ps --filter name=exercice04-ping
docker exec exercice04-ping-a ping -c 2 exercice04-ping-b
```

## Nettoyage (optionnel)

```bash
docker rm -f exercice04-ping-a exercice04-ping-b exercice04-build
docker network rm exercice04-net
# docker rmi ubuntu-ping
```
