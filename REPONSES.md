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

```
Modèle PUSH (TP 1)                     Modèle PULL (TP 2 — GitOps)
──────────────────────────────          ──────────────────────────────────────
  Dev                                     Dev
   │ git push                              │ git push
   ▼                                       ▼
  GitHub                                  GitHub (source de vérité)
   │                                       │
   ▼                                       │  polling / webhook
  CI (GitHub Actions)                    ArgoCD controller (dans le cluster)
   │ kubectl apply                         │  détecte le drift
   │ (a les droits cluster)               │  réconcilie
   ▼                                       ▼
  Cluster Kubernetes                     Cluster Kubernetes
```

**Push** : c’est la CI qui a les clés du cluster et qui pousse les changements.
**Pull** : ArgoCD tourne dans le cluster et tire lui-même l’état désiré depuis Git. La CI ne touche plus jamais au cluster.

### 2) Tableau

| Question                                                   | Push (`kubectl apply` en CI)                                              | Pull (ArgoCD)                                                                     |
| ---------------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Qui a les droits sur le cluster ?                          | La CI (GitHub Actions) — elle détient un kubeconfig avec droits cluster   | ArgoCD uniquement — les devs n’ont pas de kubeconfig                              |
| Où est l’historique des changements ?                      | Dans le Git des manifests ET dans les logs CI (deux endroits)             | Dans Git uniquement — chaque changement de cluster = un commit                   |
| Que se passe-t-il si un dev modifie le cluster à la main ? | Drift silencieux : personne ne le voit jusqu’au prochain `apply`          | ArgoCD passe immédiatement en `OutOfSync` ; si `selfHeal: true`, il corrige seul |
| Comment ajouter un environnement de plus ?                 | Copier les overlays, créer namespace, modifier la pipeline CI             | Ajouter un fichier `Application` dans `platform/apps/`. C’est tout.              |
| Comment faire un rollback ?                                | Relancer la CI sur l’ancien commit, ou `kubectl rollout undo`             | `git revert` du commit fautif — ArgoCD re-converge automatiquement               |
| Combien de pipelines pour 30 services ?                    | 30 pipelines, chacune avec accès cluster                                  | 0 pipeline ne touche au cluster ; ArgoCD centralise tout depuis `platform/`      |
| Qui voit en direct ce qui tourne ?                         | Seulement ceux qui ont accès à `kubectl` ou Freelens                      | Tout le monde avec accès à l’UI ArgoCD : version, état, sync en un coup d’œil   |

### 3) Prise de position

Pour mes futurs projets perso, je commencerais par le modèle **push** (`kubectl apply` en CI). La mise en place est immédiate et ne nécessite pas d’installer un agent supplémentaire dans le cluster. ArgoCD apporte une vraie valeur dès qu’on gère plusieurs services ou plusieurs environnements en parallèle — c’est à ce seuil que le modèle pull devient le meilleur choix.

## Étape 2

### Glossaire ArgoCD

| Terme | Définition | Exemple dans mon projet | À ne pas confondre avec… |
| ----- | ---------- | ----------------------- | ------------------------ |
| `Application` | Ressource CRD ArgoCD qui relie un dépôt Git (ou chart Helm) à un namespace cible dans le cluster. C’est l’unité de déploiement d’ArgoCD. | `annuaire-dev` : lit `services/annuaire/chart` sur `main` et déploie dans `devhub-dev` | Une application au sens métier (le service annuaire) ou au sens K8s (un Deployment) |
| `AppProject` | Périmètre de sécurité qui limite les dépôts sources autorisés, les destinations (cluster + namespace) et les ressources K8s manipulables. | `devhub` : autorise uniquement les repos du binôme et les namespaces `devhub-*` | Un projet Git ou un namespace K8s |
| `Source` | Référence exacte d’où ArgoCD lit la configuration : repoURL + path + targetRevision (branche/tag/SHA) | `repoURL: github.com/ViartFelix/infra-2-bz, path: services/annuaire/chart, targetRevision: main` | L’URL du repo Git en général — ici c’est un objet précis avec branche et chemin |
| `Destination` | Le couple `server` (URL de l’API K8s) + `namespace` où les ressources seront créées | `server: https://kubernetes.default.svc, namespace: devhub-dev` | Une URL HTTP quelconque |
| `Sync` | L’acte d’appliquer l’état décrit dans Git vers le cluster. Peut être déclenché manuellement (bouton), automatiquement (polling) ou en self-heal (correction automatique de drift) | Après un `git push` sur `values-dev.yaml`, ArgoCD sync et met à jour le Deployment | Un `kubectl apply` brut — ArgoCD gère l’ordre, les hooks et les waves en plus |
| `Prune` | Suppression des ressources présentes dans le cluster mais absentes de Git lors d’une sync. Désactivé par défaut. | Si on retire `service.yaml` du chart et que `prune: true`, ArgoCD supprime le Service K8s | Un `kubectl delete` manuel — ici c’est déclenché automatiquement par un diff Git |
| `App of Apps` | Pattern où une `Application` racine a pour source un dossier contenant d’autres manifests `Application`. Elle les crée et les gère. | `root` pointe vers `platform/apps/dev/` qui contient `annuaire.yaml`, `planning.yaml`, `notif.yaml` | Un Helm chart qui dépend d’autres charts (sub-charts) |
| `ApplicationSet` | Ressource qui génère dynamiquement plusieurs `Application` à partir d’un generator (liste, branches Git, PRs ouvertes…) | `platform/apps/preview/annuaire.yaml` : crée une Application par branche `feature/*` | Un script qui boucle — ici c’est une ressource K8s déclarative |
| `Sync wave` | Annotation (`argocd.argoproj.io/sync-wave`) qui ordonne les ressources lors d’une sync. Les waves négatives passent en premier. | `ConfigMap` en wave `-1` (appliqué avant), `Deployment` en wave `0` | Une boucle de retry ou un concept de vague de déploiement progressif |
| `Hook` (`PreSync`, `Sync`, `PostSync`) | Job ou ressource K8s annoté pour s’exécuter à une phase précise de la synchronisation. Un hook `PreSync` qui échoue bloque la sync. | Un Job de migration de schéma BDD annoté `PreSync` : il tourne avant que le Deployment soit mis à jour | Un trigger Git (webhook) ou un hook shell |

## Étape 3
### Dockerfile annuaire
![[dockerfile-annuaire.png]]

![[test-pod-annuaire.png]]

### Healthz et CURLs
Test si l'application marche correctement

![[student-list.png]]

L'endpoint `/healthz` est défini dans `src/index.js` :

```javascript
app.get('/healthz', (_, res) => res.json({ ok: true, service: 'annuaire' }));
```

Il retourne `200 OK` avec le JSON `{ "ok": true, "service": "annuaire" }`. C'est ce que les probes `readinessProbe` et `livenessProbe` du Deployment Helm interrogent.

![[test-healthz.png]]

### Push
Push sur GHCR pour voir si tout vas bien.
![[gh-push.png]]

## Étape 4

### Changements

Commit de référence : https://github.com/ViartFelix/infra-2-bz/commit/2e5cc5557a81a45e83f360badda7595db17b9f53

Le chart Helm du service `annuaire` (`services/annuaire/chart/`) a été complété avec les fichiers suivants :

**`Chart.yaml`** — métadonnées du chart (nom, version, appVersion).

**`values.yaml`** — valeurs par défaut exposant les paramètres clés :
- `image.repository` / `image.tag` / `image.pullPolicy`
- `replicaCount`
- `service.port` / `service.targetPort`
- `env.LOG_LEVEL`
- `ingress.enabled` / `ingress.host`
- `probes.readiness` / `probes.liveness` (chemin `/healthz`)
- `securityContext` (non-root, `runAsUser: 1001`, readOnly filesystem)
- `resources` (requests + limits CPU/mémoire)

**`templates/_helpers.tpl`** — helpers réutilisables : `annuaire.fullname`, `annuaire.labels`, `annuaire.selectorLabels`.

**`templates/deployment.yaml`** — Deployment paramétré via les values, avec `readinessProbe` et `livenessProbe` sur `/healthz` et `securityContext` aligné avec le `USER 1001` du Dockerfile.

**`templates/service.yaml`** — Service de type `ClusterIP` exposant le port défini dans `values.yaml`.

**`templates/ingress.yaml`** — Ingress conditionnel (`{{- if .Values.ingress.enabled }}`) sur `ingress-nginx`.

**`values-dev.yaml`** / **`values-preview.yaml`** / **`values-staging.yaml`** — surcharges par environnement (tag d'image, nombre de répliques, host d'ingress, LOG_LEVEL).

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

### selfHeal vs prune : comparaison et cas dangereux

**`selfHeal: true`** — ArgoCD surveille en permanence l'état réel du cluster. Si quelqu'un modifie une ressource à la main (`kubectl edit`, `kubectl scale`…), ArgoCD la remet automatiquement à l'état décrit dans Git dans les secondes qui suivent.

*Cas où c'est dangereux :* un SRE fait un `kubectl scale deploy annuaire --replicas=0` en urgence pour couper le trafic pendant un incident. ArgoCD voit le drift et remet immédiatement les répliques à 2. Le service redémarre contre la volonté de l'opérateur. Sur un cluster de prod avec `selfHeal: true`, toute intervention manuelle d'urgence est écrasée sans délai.

**`prune: true`** — lors d'une sync, ArgoCD supprime du cluster toutes les ressources qui ne sont plus présentes dans Git.

*Cas où c'est dangereux :* on renomme un fichier `service.yaml` en `svc.yaml` dans le chart sans changer son contenu. Helm génère la même ressource K8s, mais ArgoCD voit l'ancien `Service` comme "absent de Git" et le supprime — coupant le trafic vers tous les pods — avant même de créer le nouveau. Sur un service exposé en prod, ça provoque une interruption de service non planifiée le temps du sync.

## Etape 6

### Config root-app.yaml

Pourquoi `prune: false` et `selfHeal: true` sur la root Application :
- **selfHeal: true** — Git est la source de vérité. Si quelqu'un modifie une ressource à la main, ArgoCD la remet dans l'état décrit sur `main` automatiquement.
- **prune: false** — on ne veut pas qu'une erreur de chemin ou un commit accidentel supprime toutes les Applications enfants d'un coup. Sur la root, `prune: true` serait trop risqué : supprimer un fichier `annuaire.yaml` de `platform/apps/dev/` détruirait instantanément tout le service en dev.

![[root-app.png]]

### Pourquoi App of Apps ≠ `kubectl apply -f apps/dev/`

Un `kubectl apply -f platform/apps/dev/` crée les ressources `Application` une seule fois, de façon impérative. Si on ajoute ensuite un fichier dans ce dossier, il faut relancer la commande manuellement. Si on en supprime un, il faut faire un `kubectl delete` séparé. La CI doit avoir accès au cluster pour le faire.

Avec le pattern **App of Apps**, la root `Application` surveille en continu le dossier `platform/apps/dev/` dans Git. Ajouter un service = commiter un fichier YAML. Le supprimer = le retirer de Git. ArgoCD détecte le changement et crée ou supprime les Applications enfants automatiquement, sans que personne ne touche au cluster. C'est la même logique GitOps appliquée à ArgoCD lui-même : l'outil se gère via Git, pas via des commandes impératives.

### Screenshot — 4 Applications dans l'UI ArgoCD
![[4-services.png]]

## Etape 7

### Choix du generator : `pullRequest`

On utilise le generator **`pullRequest`** plutôt que `git`. Raison : le `pullRequest` generator génère une `Application` par PR ouverte sur le repo, ce qui correspond exactement au besoin de preview éphémère — la preview apparaît quand la PR est ouverte, disparaît quand elle est mergée ou fermée. Le `git` generator sur branches est plus simple mais moins précis : il génère une preview pour toute branche existante, même sans PR associée.

### Token GitHub

Création d'un Personal Access Token (classic) avec le scope `repo` uniquement, pour que ArgoCD puisse lire les PRs via l'API GitHub sans droits superflus.

![[token-creation.png]]

Le token est stocké dans le cluster en tant que Secret Kubernetes dans le namespace `argocd` :

```bash
kubectl create secret generic github-token \
  --from-literal=token=<TOKEN> \
  -n argocd
```

### ApplicationSet annuaire-preview

L'`ApplicationSet` génère automatiquement une `Application` par PR ouverte sur le repo. Chaque preview est déployée dans son propre namespace `devhub-preview-<branch_slug>` et exposée sur son propre ingress.

`prune: true` est indispensable ici : quand la PR est fermée/mergée, ArgoCD supprime l'`Application` générée et donc toutes les ressources K8s associées. Sans `prune`, les previews s'accumulent indéfiniment.

### PR de démonstration

Ouverture d'une PR depuis la branche `feature/demo-preview` vers `main`. Le `pullRequest` generator d'ArgoCD interroge l'API GitHub toutes les 60 secondes (`requeueAfterSeconds: 60`) et détecte la PR ouverte.

![[pr_demo_open.png]]

Dans la minute suivant l'ouverture de la PR, ArgoCD génère automatiquement une `Application` nommée `annuaire-preview-feature-demo-preview` dans le namespace `devhub-preview-feature-demo-preview`, sans aucune intervention manuelle sur le cluster.

![[app_preview_argocd.png]]

### Suppression de la preview

Fermeture de la PR sur GitHub. ArgoCD détecte la disparition de la PR lors du prochain polling (60 secondes) et supprime automatiquement l'`Application` générée grâce à `prune: true`.

![[pr_close.png]]

L'UI ArgoCD après suppression : l'Application `annuaire-preview-feature-demo-preview` a disparu, ainsi que toutes les ressources K8s associées dans le namespace `devhub-preview-feature-demo-preview`. Aucune commande `kubectl delete` n'a été nécessaire.

![[argocd_post_pr_close.png]]


## Étape 8 — Drift, rollback, hooks, sync waves

### 1. Drift et selfHeal

**Manipulation :** `kubectl scale deploy annuaire-dev-annuaire -n devhub-dev --replicas=5`

**Observation :** ArgoCD a détecté le drift et corrigé automatiquement le nombre de répliques à `1` (valeur de `values-dev.yaml`) avant même qu'on puisse voir l'état `OutOfSync` dans l'UI. Le Deployment est immédiatement revenu à son état Git.

**Conclusion :** avec `selfHeal: true`, tout changement manuel sur le cluster est écrasé quasi instantanément. C'est la promesse GitOps : Git est l'unique source de vérité. Un opérateur qui tente une intervention d'urgence via `kubectl` verra son changement annulé sans avertissement.

![[drift_command.png]]

![[drift_creation.png]]

---

### 2. Image inexistante — Synced + Degraded

**Manipulation :** commit qui change `image.tag` pour un tag qui n'existe pas (`tag-qui-nexiste-pas`).

![[inexistant_tag.png]]

**Observation :** ArgoCD sync avec succès côté manifest (le YAML est valide), mais le pod reste en `ImagePullBackOff`. L'Application affiche `Synced + Degraded` — ArgoCD a bien appliqué ce que Git décrivait, mais Kubernetes ne peut pas exécuter le pod.

**Conclusion :** ArgoCD ne valide pas que l'image existe réellement avant de syncer. `Synced` signifie "Git appliqué", pas "service fonctionnel". C'est pourquoi `Degraded` peut coexister avec `Synced`.

![[synced_degraded.png]]

---

### 3. Rollback par git revert

**Manipulation :** commit qui change `image.tag` en `tag-rollback-demo` (inexistant) dans `values.yaml`, push sur `main`, puis `git revert HEAD --no-edit` et re-push.

Changement du tag dans `values.yaml` et push :

![[tag_change.png]]

**Observation intermédiaire :** le nouveau pod passe en `ErrImagePull` mais l'ancien pod reste `Running` grâce au rolling update — le service reste disponible. ArgoCD affiche `Progressing + Synced`.

![[ui_tagweb.png]]

![[ui_tag_result.png]]

**Revert :** `git revert HEAD --no-edit && git push`, puis `git pull` en WSL2 pour récupérer le commit de revert :

![[git_pull_revert.png]]

**Observation finale :** ArgoCD détecte le commit de revert, re-sync automatiquement, le pod repart avec le tag `6f54102`. Le service redevient `Healthy + Synced`.

![[ui_web_after.png]]

**Conclusion :** le rollback GitOps se fait en une commande Git, sans toucher au cluster. L'historique est préservé (le revert crée un commit, il n'efface pas l'historique). Point notable : le rolling update Kubernetes maintient l'ancien pod en vie pendant la tentative de déploiement du mauvais tag — le service ne subit aucune interruption.

---

### 4. Hook PreSync — migration avant déploiement

**Manipulation :** ajout d'un Job annoté `argocd.argoproj.io/hook: PreSync` et `hook-delete-policy: HookSucceeded` dans `services/annuaire/chart/templates/presync-hook.yaml`. Le Job simule une migration BDD avec `echo 'migration ok'`.

![[presync_hook.png]]

**Observation :** à la sync suivante (`argocd app sync annuaire-dev`), le Job `annuaire-dev-annuaire-migrate` est créé et passe `Running → Succeeded` (statut `PreSync`) **avant** que le Deployment, le Service et l'Ingress ne soient touchés. La sync totale dure 6 secondes. Le Job est ensuite supprimé automatiquement (`HookSucceeded`).

![[synced_app.png]]

**Conclusion :** les hooks `PreSync` permettent de garantir l'ordre des opérations — typiquement une migration de schéma BDD avant le déploiement du nouveau code. Un hook qui échoue bloque la sync : le Deployment n'est pas mis à jour, ce qui évite de mettre en production du code incompatible avec l'ancien schéma.

---

### 5. Sync waves — ordre d'application des ressources

**Manipulation :** ajout d'un `ConfigMap` (`configmap.yaml`) annoté `argocd.argoproj.io/sync-wave: "-1"` et annotation `argocd.argoproj.io/sync-wave: "0"` sur le Deployment.

![[update_services.png]]

**Observation :** à la sync, ArgoCD applique d'abord le ConfigMap (wave -1) à 12:23:36, puis le Job PreSync à 12:23:38, et enfin le Deployment, le Service et l'Ingress (wave 0) à 12:23:42. L'ordre est garanti : la wave 0 ne démarre pas tant que la wave -1 n'est pas `Synced`.

![[pull_manip_5.png]]

L'UI ArgoCD après sync montre le ConfigMap `annuaire-dev-annuaire-config` bien présent dans le graphe de ressources, créé "a minute ago" contrairement aux autres ressources à "3 days".

![[sync_waves.png]]

**Conclusion :** les sync waves permettent de contrôler l'ordre d'application des ressources au sein d'une même sync. Différent des hooks : les waves s'appliquent à des ressources K8s permanentes (ConfigMap, Secret, CRD…), les hooks sont des Jobs éphémères exécutés à une phase précise de la sync.

---

### 6. Prune — suppression via Git

**Manipulation :** passage de `prune: false` à `prune: true` dans `platform/apps/dev/annuaire.yaml` + suppression de `services/annuaire/chart/templates/service.yaml`, commit et push. Sync forcé avec `argocd app sync annuaire-dev --grpc-web --prune`.

Commit montrant les deux changements (`annuaire.yaml` avec `prune: true` et suppression de `service.yaml`) :

![[prune_delete_ide.png]]

**Observation :** la sync passe en `Automated (Prune)`. Le Service `annuaire-dev-annuaire` est supprimé du cluster. `kubectl get svc -n devhub-dev` ne liste plus que les services de `notif` et `planning` — `annuaire` a disparu.

![[sync_prune_cmd.png]]

![[missing_devhub_web.png]]

L'UI ArgoCD confirme : le nœud `svc` a disparu du graphe de ressources. L'Application reste `Healthy + Synced` car Kubernetes ne voit plus de Service à reconcilier.

![[devhub_web_missing_ui.png]]

**Conclusion :** `prune: true` rend Git la source de vérité absolue — toute ressource absente de Git disparaît du cluster à la prochaine sync. Puissant mais dangereux : supprimer un fichier par erreur supprime la ressource K8s en production sans avertissement préalable.

---

## Étape 9 — Sécuriser et observer ArgoCD

### 1. RBAC

**Configuration :** ajout d'un compte local `developer` et de deux rôles dans `platform/argocd/values.yaml` :

- `platform-admin` : tous les droits sur applications, projets, dépôts et clusters.
- `developer` : lecture (`get`) sur toutes les apps du projet `devhub`, sync autorisé uniquement sur `annuaire-*`.

![[argocd_value_edit.png]]

Déploiement avec `helm upgrade argocd argo/argo-cd -n argocd -f platform/argocd/values.yaml` :

![[help_update.png]]

Création du mot de passe du compte `developer` via `argocd account update-password` :

![[dev_password_reset.png]]

**Test RBAC :** connexion en tant que `developer`, tentative de sync sur `root` (refusée) puis sur `annuaire-dev` (accordée) :

![[rpc_error_with_sync.png]]

**Conclusion :** le compte `developer` reçoit bien un `PermissionDenied` sur `root` (hors de son périmètre) et peut syncer `annuaire-dev` sans restriction. Le RBAC ArgoCD utilise un mini-DSL (`policy.csv`) avec des règles `p, role, resource, action, scope, effect` et des bindings `g, user, role`.

---

### 2. Notifications

**Configuration :** activation de `argocd-notifications` dans `platform/argocd/values.yaml` avec un service webhook pointant sur webhook.site, un trigger `on-sync-failed` et un template JSON contenant le nom de l'Application, la révision et l'erreur.

**Déclenchement :** un hook `PreSync` volontairement défaillant (`exit 1`) provoque un `Phase: Failed` sur `annuaire-dev`. ArgoCD envoie automatiquement un `POST application/json` sur webhook.site.

![[webhook_response.png]]

Le payload reçu :
```json
{
  "application": "annuaire-dev",
  "revision": "53763d685b813b2452bd9b66d930bc8b1ea178e8",
  "error": "one or more synchronization tasks completed unsuccessfully"
}
```

**Conclusion :** une sync échouée déclenche la notification en quelques secondes. En production, ce webhook serait remplacé par un endpoint Slack ou PagerDuty pour alerter l'équipe en temps réel.

---

### 3. Observabilité — métriques Prometheus

Les métriques sont exposées par `argocd-application-controller` sur le port `8082/metrics`. Accès via `kubectl port-forward pod/argocd-application-controller-0 -n argocd 8082:8082`.

![[metrics_screen.png]]

**Trois métriques utiles :**

| Métrique | Unité | Utilité en cas d'incident |
|---|---|---|
| `argocd_app_info` | gauge (0/1 par app) | Donne en temps réel le `health_status` et `sync_status` de chaque Application. Si `health_status != "Healthy"` ou `sync_status != "Synced"`, une alerte peut être déclenchée. |
| `argocd_app_k8s_request_total` | counter (nb de requêtes) | Compte les appels K8s par app et type de ressource. Un pic soudain indique une boucle de réconciliation ou une tempête de drift — signe qu'une ressource est modifiée en continu hors Git. |
| `argocd_app_reconcile_count` | counter (nb de réconciliations) | Nombre total de cycles de réconciliation par app. Une valeur qui monte très vite sans sync correspondante indique un drift permanent non résolu — l'app est en conflit continu avec l'état du cluster. |
