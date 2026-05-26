# Partie I

## Étape 0 - Outillage

| Commande                 | Version                                                                                                                                                                                                             |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| kubectl version --client | Client Version: v1.35.3                                                                                                                                                                                             |
| helm version             | version.BuildInfo{Version:"v3.20.0", GitCommit:"b2e4314fa0f229a1de7b4c981273f61d69ee5a59", GitTreeState:"clean", GoVersion:"go1.25.6"}                                                                              |
| argocd version --client  | argocd: v3.4.2+0dc6b1b<br>  BuildDate: 2026-05-12T21:00:01Z<br>  GitCommit: 0dc6b1b57dd5bb925d5b03c3d09419ab9fb4225e<br>  GitTreeState: clean<br>  GoVersion: go1.26.0<br>  Compiler: gc<br>  Platform: linux/amd64 |
### Argo update password
![[argo-updated-password.png]]

### Cluster Up
![[cluster-up.png]]

### Fichier Host
![[hosts.png]]

## Étape 1 -  Comprendre GitOps avant d’écrire la moindre ligne
### 1) Schéma

### 2) Tableau

| Question                                                   | Push(kubectl apply en CI) | Pull (ArgoCD) |
| ---------------------------------------------------------- | ------------------------- | ------------- |
| Qui a les droits sur le cluster ?                          |                           |               |
| Où est l’historique des changements ?                      |                           |               |
| Que se passe-t-il si un dev modifie le cluster à la main ? |                           |               |
| Comment ajouter un environnement de plus ?                 |                           |               |
| Comment faire un rollback ?                                |                           |               |
| Combien de pipelines pour 30 services ?                    |                           |               |
| Qui voit en direct ce qui tourne ?                         |                           |               |

### 3) Prises de position
## Étape 2

## Étape 3
### Dockerfile annuaire
![[dockerfile-annuaire.png]]

![[test-pod-annuaire.png]]

### Healthz et CURLs
Test si l'application marche correctement

![[student-list.png]]

TODO: mettre le code pour le healthz
![[test-healthz.png]]

### Push
Push sur GHCR pour voir si tout vas bien.
![[gh-push.png]]

## Étape 4

### Changements
TODO: mettre les changements des fichiers mentionnés dans le commit ci-dessous.
https://github.com/ViartFelix/infra-2-bz/commit/2e5cc5557a81a45e83f360badda7595db17b9f53

### Commandes Helm
![[commandes-helm.png]]

## Étape 5

### Installation d'argoCD
![[argo-install.png]]


![[argo-interface.png]]
### Services
On ne modifie qu'un seul des 3 services (ici annuaire, pas les autres qui sont notifs et planning) Puis on vient appliquer nos changement
![[one-service.png]]

### Synchro argoCD avec le repo
![[argo-sync.png]]

![[before-sync-2.png]]


![[argo-sync-2.png]]

## Etape 6
Config du root-app.yaml : Pourquoi prune à false et selfHeal à true :
- selfHeal = se base sur le main et applique les changements qui sont sur la main donc le git est source de vérité
- prune = Suppression si différent, exemple si je supprime une ressource accidentellement alors cela sera considéré comme un changement et argo supprimera celle-ci.

![[root-app.png]]