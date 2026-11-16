# Rendu TP 2 : Optimisation Docker

*Objectif : Optimiser le Dockerfile et l'image d'une petite app Node.js étape par étape.*

## Étape 0 : État des lieux (Baseline)

Pour avoir un point de comparaison, j'ai commencé par build le projet tel qu'il a été fourni.
*Note : j'ai temporairement retiré le `.dockerignore` pour ce test car le Dockerfile d'origine fait un `COPY node_modules` que le `.dockerignore` exclut : le build aurait échoué.*

Mesure du temps de build :
```bash
$ time docker build -f dockerfile -t tp2:baseline .
...
real    1m18.273s
user    0m0.330s
sys     0m0.174s
```

Mesure de la taille de l'image :
```bash
$ docker images tp2:baseline
IMAGE          ID             DISK USAGE   CONTENT SIZE   EXTRA
tp2:baseline   3e2e12a8338f       1.88GB          474MB
```

**Bilan de départ :** Le build prend plus d'une minute (téléchargement de `node:latest` compris) et `docker images` affiche **1.88 GB** (environ 1.4 GB de couches décompressées + 474 MB compressés, voir étape 1). C'est optimisable


## Étape 1 : Le `.dockerignore`

La première optimisation est de ne pas envoyer tout et n'importe quoi au daemon Docker. 
- J'ai rempli le `.dockerignore` pour exclure `node_modules`, `.git`, les logs et le `.env`.
- Du coup j'ai retiré la ligne `COPY node_modules ./node_modules` du Dockerfile (puisque le dossier est maintenant ignoré, et de toute façon la commande `RUN npm install` est là pour ça).

Impact sur le contexte de build :
```bash
$ du -sh node_modules
14M     node_modules

$ time docker build --no-cache --progress=plain -f dockerfile -t tp2:01-dockerignore . 2>&1 | grep "transferring context"
#4 transferring context: 69B done
#7 transferring context: 48.10kB 0.0s done
```

Impact sur l'image :
```bash
$ docker images tp2
IMAGE                 ID             DISK USAGE   CONTENT SIZE
tp2:01-dockerignore   35fa5a8f3f38       1.89GB          477MB
tp2:baseline          3e2e12a8338f       1.88GB          474MB
```

**Résultat :** Le poids du contexte envoyé à Docker passe de **14 Mo à 48 Ko**. C'est beaucoup plus propre. 
La taille de l'image ne baisse pas (1.89 GB contre 1.88 GB) : le poids vient de l'image de base, voir les layers ci-dessous. 
*Note : Pour les prochaines étapes, je comparerai les temps de build en utilisant `--no-cache` pour ne pas fausser les résultats.*

Pour savoir d'où vient le poids, j'ai regardé les layers :
```bash
$ docker history tp2:01-dockerignore
CREATED BY                                      SIZE
RUN npm run build                               36.9kB
RUN apt-get update && apt-get ins…              50.1MB
RUN npm install                                 25.8MB
COPY . /app                                     81.9kB
WORKDIR /app                                    8.19kB
(couches de node:latest)                        696MB, 240MB, 202MB, 134MB, 65MB

$ docker run --rm tp2:01-dockerignore du -sh /root/.npm /app/node_modules
7.0M    /root/.npm
16M     /app/node_modules
```

**Analyse :**
- Les couches de `node:latest` (Debian + Node 26.13.0) font environ 1.34 GB sur 1.41 GB au total. Mes instructions n'ajoutent que ~76 MB (`apt-get` 50.1 MB, `npm install` 25.8 MB). Le `.dockerignore` agit sur le contexte envoyé à Docker, pas sur les couches de l'image de base, d'où l'absence de gain sur la taille.
- Le layer `npm install` contient `node_modules` (16 MB, avec `nodemon` qui est une devDependency) et le cache npm (7 MB), inutile à l'exécution.
- Les layers sont immuables : supprimer un fichier dans un layer suivant ne réduit pas l'image. Pour ne pas garder le cache, il faut le nettoyer dans le même `RUN` (comme l'exemple `apt-get ... && rm -rf /var/lib/apt/lists/*` du cours).
- DISK USAGE (1.89 GB) = layers décompressés (~1.41 GB, somme de `docker history`) + contenu compressé stocké par Docker (477 MB).


## Étape 2 : Alléger l'image de base

Pour bien comprendre l'impact de chaque optimisation j'ai découpé cette étape en deux.

### 2a. Suppression des `apt-get`

Le Dockerfile de base installait `build-essential`, `ca-certificates` et `locales`. Avant de supprimer, j'ai vérifié si l'app dépendait de modules natifs (fichiers `.node` compilés) :
```bash
$ find node_modules -name "*.node" | wc -l
0
```
Aucune dépendance ne compile de code natif donc pas besoin de compilateur et l'app n'utilise pas les locales. 
J'ai supprimé la ligne.
```bash
$ docker images tp2
IMAGE                 ID             DISK USAGE   CONTENT SIZE
tp2:01-dockerignore   35fa5a8f3f38       1.89GB          477MB
tp2:02a-sans-apt      2725b6d4aeb1       1.82GB          451MB
```
Résultat : on gagne 70 MB d'espace disque et 26 MB de CONTENT SIZE. la commande `docker history` montrait que la couche apt-get pesait 50.1 MB (qui se compresse en 26 MB gagnés en Content Size).
Le temps de build n'est pas très pertinent ici (fluctuations liées au réseau).


### 2b. `node:latest` vers `node:26-alpine`

L'image `node:latest` embarque une distribution Debian complète lourde. Je passe sur Alpine en gardant Node 26 pour ne changer que l'OS.
```bash
$ docker images tp2
IMAGE                 ID             DISK USAGE   CONTENT SIZE
tp2:02a-sans-apt      2725b6d4aeb1       1.82GB          451MB
tp2:02b-alpine        3934bea22fac        284MB         69.3MB

$ docker history tp2:02b-alpine
CREATED BY                                      SIZE
RUN npm install                                 25.8MB
COPY . /app                                     81.9kB
WORKDIR /app                                    8.19kB
RUN addgroup -g 1000 node && ...                179MB
ADD alpine-minirootfs-3.24.4-x86_64.tar.gz /    9.09MB
```
Test que l'app marche toujours :
```bash
$ docker run -d --rm -p 3000:3000 --name tp2 tp2:02b-alpine
$ curl localhost:3000
Hello world — serveur volontairement non optimisé mais fonctionnel
```

**Analyse :**
- On passe de 1.82 GB à 284 MB, et 451 MB devient 69.3 MB en compressé. Par rapport à la baseline, on est à -85 %.
- Les couches de l'image de base passent d'environ 1.34 GB à 188 MB.
- La version de Node a changé de 26.13.0 à 26.13.1 entre les deux builds. C'est un patch, négligeable face au gain.

**Bilan pour la suite :**
- Node représente maintenant 179 MB soit environ 83 % du poids de l'image. On ne pourra plus réduire beaucoup la taille. Les prochaines étapes d'optimisation viseront surtout l'architecture des couches (utilisation du cache) pour accélérer le rebuild.


## Étape 3 : Ordre des layers (cache)

Docker met en cache chaque instruction, et dès qu'une couche change toutes les suivantes sont reconstruites. Dans le Dockerfile de départ, `COPY . /app` était placé avant `RUN npm install` donc la moindre modification de code relançait `npm install`, même si `package.json` n'avait pas bougé.

Mesure avant (rebuild avec cache après un petit changement dans `server.js`) :
```bash
$ time docker build -f dockerfile -t tp2:03-avant-rebuild .
 => CACHED [2/5] WORKDIR /app
 => [3/5] COPY . /app                      0.4s
 => [4/5] RUN npm install                  2.7s
 => [5/5] RUN npm run build                0.4s
 => exporting to image                     1.1s
real    0m4.937s
```

J'ai réorganisé le `Dockerfile` pour copier uniquement les fichiers qui définissent les dépendances d'abord, puis les installer, et enfin copier le reste du code (qui change souvent) :
```dockerfile
COPY package*.json ./
RUN npm install
COPY . .
```

### Mesure de l'impact ("Après")
Je refais une modification dans `server.js` et je relance le build :
```bash
$ time docker build -f dockerfile -t tp2:03-apres-rebuild .
 => CACHED [2/6] WORKDIR /app
 => CACHED [3/6] COPY package*.json ./
 => CACHED [4/6] RUN npm install
 => [5/6] COPY . .                         0.4s
 => [6/6] RUN npm run build                0.4s
 => exporting to image                     0.2s
real    0m1.372s
```

**Résultat :** le rebuild passe de 4.9 s à 1.4 s (-72 %).

**Analyse :**
- Les 3.6 s gagnés viennent de `npm install` (2.7 s) et de l'export de l'image (0.9 s) car la couche `npm install` de 25.8 MB n'est plus reconstruite.
- La taille de l'image ne change pas ,on a seulement réordonné les instructions.
- Le premier build n'est pas plus rapide. Le gain n'existe que sur les rebuilds.
- Ici l'app est petite (`npm install` dure environ 3 s). Le gain est proportionnel au temps d'installation des dépendances donc plus visible sur un gros projet.
- J'ai testé en ajoutant un fichier au projet (`note.txt`, puis `note2.txt`) : seul `COPY . .` est relancé et `npm install` reste `CACHED`. C'est pareil pour le `README.md`, qui n'est pas dans le `.dockerignore` : modifier la doc ne relance plus `npm install`. (Un tout premier essai avec `note.txt` avait affiché `COPY . .` en `CACHED`, sans que je sache l'expliquer ; refait ensuite, le résultat était conforme.)


## Étape 4 : Faire le tri dans les dépendances

### 4a. Installation propre pour la prod (`npm ci --omit=dev`)

Jusqu'ici, mon `RUN npm install` installait tout, y compris les *devDependencies* comme `nodemon` (rechargement à chaud en développement), inutile ici puisque le conteneur se lance avec `node server.js`.

J'ai donc remplacé cette ligne par :
```dockerfile
RUN npm ci --omit=dev && npm cache clean --force
```

Pourquoi cette commande ?
- `npm ci` : build reproductible, basé strictement sur le `package-lock.json`.
- `--omit=dev` : exclut les dépendances de développement.
- `npm cache clean --force` : vide le cache npm dans la même instruction `RUN`. Les layers Docker étant immuables, le faire dans un `RUN` séparé n'aurait pas réduit la taille de l'image.

Mesure de l'impact :
```bash
$ docker images tp2
IMAGE                  ID             DISK USAGE   CONTENT SIZE
tp2:03-apres           2e150e712e8c        284MB         69.3MB
tp2:04a-prod-deps      0a61426dcc84        271MB         65.9MB

$ docker run --rm tp2:04a-prod-deps du -sh /app/node_modules /root/.npm
13.2M   /app/node_modules
60.0K   /root/.npm
```

Résultat : -13 MB en DISK USAGE (-3.4 MB en CONTENT SIZE). `node_modules` passe de 16 MB à 13.2 MB et le cache npm de 7.0 MB à 60 KB (valeurs de l'étape 1, mesurées sur l'image Debian ; le layer `npm install` faisait la même taille sur Alpine). Nettoyer le cache fait donc gagner plus de place que retirer `nodemon`.

### 4b. Suppression d'une dépendance inutilisée (`mongodb`)

En regardant le `package.json`, `mongodb` est dans les `dependencies`, donc `--omit=dev` ne la retire pas. Pour vérifier si elle sert, j'ai cherché dans le code :
```bash
$ grep -n "require" server.js
1:const express = require('express');
2:const fs = require('fs');
3:const path = require('path');

$ grep -n "mongodb" server.js
(aucun résultat)
```

`mongodb` n'est appelé nulle part (`fs` et `path` sont intégrés à Node). Je l'ai désinstallée avec `npm uninstall mongodb`, qui met à jour `package.json` et `package-lock.json` (nécessaire pour que `npm ci` continue de fonctionner).

Mesure de l'impact :
```bash
$ docker images tp2
IMAGE                  ID             DISK USAGE   CONTENT SIZE
tp2:04a-prod-deps      0a61426dcc84        271MB         65.9MB
tp2:04b-sans-mongodb   398eec5d16d7        260MB         64.2MB

$ docker run --rm tp2:04b-sans-mongodb du -sh /app/node_modules
4.4M    /app/node_modules
```

Test de fonctionnement (un `curl` lancé juste après `docker run` a échoué, probablement parce que le serveur n'écoutait pas encore, d'où le `sleep 2`) :
```bash
$ docker run -d --rm -p 3000:3000 --name tp2 tp2:04b-sans-mongodb
$ sleep 2
$ curl localhost:3000
Hello world — serveur volontairement non optimisé mais fonctionnel
$ docker logs tp2
Serveur démarré sur le port 3000
[2026-11-16T17:23:51.816Z] GET /
```

**Analyse :**
- -11 MB en DISK USAGE : `node_modules` passe de 13.2 MB à 4.4 MB, donc `mongodb` et ses sous-dépendances représentaient les deux tiers des dépendances de production.
- Le gain compressé (-1.7 MB) est bien plus faible que le gain décompressé (-9 MB environ) : le JavaScript se compresse bien.
- Bilan par rapport à la baseline : l'image passe de 1.88 GB à 260 MB (-86 %), et de 474 MB à 64.2 MB en compressé (-86 %).
- Remarque : `npm uninstall` a signalé 11 vulnérabilités (dont 1 critique). Cet audit inclut les devDependencies, et je n'ai pas lancé `npm audit fix` car ça change des versions, hors du périmètre de ce TP.


## Étape 5 : Multi-stage build

Un Dockerfile peut avoir plusieurs `FROM`.C'est le dernier stage qui  devient l'image finale, et `COPY --from=` permet de récupérer des fichiers d'un stage précédent. Le reste n'est pas embarqué.
Ici le `npm run build` ne fait qu'un `echo` et ne produit aucun fichier donc je m'attends à un gain faible.

### 5a. Deux stages : `deps` et image finale

```dockerfile
FROM node:26-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM node:26-alpine
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
...
```
Le `COPY . .` n'écrase pas `node_modules` car le `.dockerignore` l'exclut du contexte.

```bash
$ docker images tp2
IMAGE                  ID             DISK USAGE   CONTENT SIZE
tp2:04b-sans-mongodb   398eec5d16d7        260MB         64.2MB
tp2:05-multistage      5136195c87d2        259MB         64.1MB
```
Résultat : 1 MB en moins seulement, le multi-stage n'apporte rien à lui seul.
Dans le `docker history` la couche `RUN npm run build` est passée de 36.9 kB à 2.05 MB. Probablement parce que l'étage final n'avait jamais lancé npm donc ce premier appel à créé des fichiers de travail (`/root/.npm`).

### 5b. Faire le build dans le stage `builder`

Je déplace `COPY . .` et `RUN npm run build` dans le premier stage (`builder`) et l'image finale récupère juste le résultat :
```dockerfile
FROM node:26-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY . .
RUN npm run build

FROM node:26-alpine
WORKDIR /app
COPY --from=builder /app ./
...
```
```bash
$ docker images tp2
IMAGE                  ID             DISK USAGE   CONTENT SIZE
tp2:05-multistage      5136195c87d2        259MB         64.1MB
tp2:05b-builder        4480c0474d33        257MB         63.7MB

$ docker run --rm tp2:05b-builder du -sh /root/.npm
du: /root/.npm: No such file or directory
```
Test que l'app marche toujours :
```bash
$ docker run -d --rm -p 3000:3000 --name tp2 tp2:05b-builder
$ sleep 2
$ curl localhost:3000
Hello world — serveur volontairement non optimisé mais fonctionnel
```

**Coclusion :**
- Le multi-stage seul ne réduit rien. Les 2 MB gagnés viennent du fait de ne plus lancer npm dans l'image finale : la couche `RUN npm run build` a disparu et il n'y a plus de dossier `/root/.npm`
- Sur toute l'étape on passe de 260 MB à 257 MB car l'app n'a pas de vrai build
- L'intérêt est la structure : pour une app avec un vrai build (TypeScript, React...) on installerait toutes les dépendances dans `builder` et on ne copierait que le résultat compilé dans l'image finale
- Bilan par rapport à la baseline, 1.88 GB → 257 MB (-86 %) et 474 MB → 63.7 MB en compressé
- Node représente maintenant environ 93 % de l'image donc il reste très peu à gagner sur la taille