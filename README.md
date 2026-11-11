# Rendu TP 2 : Optimisation Docker

*Objectif : Optimiser le Dockerfile et l'image d'une petite app Node.js étape par étape.*

## Étape 0 : État des lieux (Baseline)

Pour avoir un point de comparaison, j'ai commencé par build le projet tel qu'il a été fourni.
*Note : j'ai temporairement retiré le `.dockerignore` pour ce test car le Dockerfile d'origine fait un `COPY node_modules` qui plantait avec.*

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

**Bilan de départ :** Le build prend plus d'une minute et l'image pèse un énorme **1.88 GB** C'est optimisable


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
La taille finale de l'image ne bouge pas encore (c'est l'image de base `node:latest` qui pèse  lourd). 
*Note : Pour les prochaines étapes, je comparerai les temps de build en utilisant `--no-cache` pour ne pas fausser les résultats.*