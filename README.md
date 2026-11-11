# TP2-OptimisationDocker

Optimisation d'une petite application Node.js et de son Dockerfile.

## Etape 0 : Baseline

- Import du projet du TP, avec un `.gitignore` pour ne pas versionner `node_modules`

- Build de l'image avec le Dockerfile d'origine, sans rien changer.
J'ai enlevé le `.dockerignore` le temps de la mesure, car le Dockerfile copie `node_modules` alors que le `.dockerignore` l'exclut.
```
$ time docker build -f dockerfile -t tp2:baseline .
...
real    1m18.273s
user    0m0.330s
sys     0m0.174s
```

- Taille de l'image
```
$ docker images tp2:baseline
IMAGE          ID             DISK USAGE   CONTENT SIZE   EXTRA
tp2:baseline   3e2e12a8338f       1.88GB          474MB
```

Résultat : 1.88 GB sur le disque (474 MB compressée), build en 1 min 18 s.
(DISK USAGE = taille décompressée, CONTENT SIZE = taille compressée)

## Ajout d'un .dockerignore

- Action : Création d'un fichier `.dockerignore` pour exclure `node_modules`.
- Impact : Évite de copier les dépendances locales dans le contexte de build. Réduit le temps de build et évite les conflits d'architecture.