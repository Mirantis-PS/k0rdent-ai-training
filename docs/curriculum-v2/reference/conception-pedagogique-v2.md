# k0rdent AI Training — V2
## Concevoir, déployer, comprendre et opérer une plateforme IA

**Statut :** proposition de conception pédagogique. Ce document n'est pas une release exécutable et validée du cours. Le dépôt distant n'a pas été modifié. Les nouvelles manipulations et variantes matérielles proposées n'ont pas été exécutées pendant cette revue.

**Référence examinée :** branche publique `main` de `Mirantis-PS/k0rdent-ai-training`, consultée le 6 octobre 2026. Les pages ont été consultées via le Web ; aucun SHA immuable n'a été capturé. Avant implémentation, figer le commit source et le contrat de compatibilité.

**Public :** ingénieurs Mirantis disposant des prérequis Kubernetes/Linux/IaC du programme existant, sans connaissances préalables exigées en infrastructure IA.

**Contraintes conservées :** k0rdent et k0rdent AI constituent le fil conducteur ; majorité de hands-on ; conservation des acquis de Week 1 et du contenu investi dans Week 5 ; abandon des weeks et des étapes BMaaS/VMaaS/KaaS imposées ; dépendance minimale aux GPU chers ou rares. Les sources produit k0rdent AI restent à fournir.

---

## 1. L'objectif professionnel

À l'issue du parcours commun, l'ingénieur doit pouvoir prendre en charge une plateforme IA de référence : la déployer avec k0rdent AI, expliquer les choix de ressources et de runtime, mesurer son comportement, traiter un incident, puis livrer une configuration reproductible et un dossier d'exploitation.

L'expertise n'est pas évaluée au nombre de produits installés. Elle est démontrée par cinq capacités : construire, expliquer, mesurer, diagnostiquer et transférer.

La formation distingue trois niveaux de preuve pour chaque compétence :

- **Compris :** l'ingénieur explique un mécanisme et interprète des résultats fournis.
- **Réalisé :** il a exécuté la manipulation sur du matériel compatible.
- **Maîtrisé :** il sait refaire la tâche avec des paramètres nouveaux et traiter une panne sans recette complète.

Ces niveaux évitent notamment de présenter une analyse de traces NVLink ou RDMA comme une qualification pratique à l'exploitation de ces fabrics.

## 2. Ce qui change par rapport au programme actuel

Les deux piliers sont le socle de déploiement de Week 1 et les workloads de Week 5. Leur contenu devient une bibliothèque de séquences réutilisées dans une progression par compétences.

Week 1 est conservée intégralement sur le fond, mais n'est plus un bloc qui doit nécessairement être terminé avant de voir le premier modèle. Le déploiement, le provider et le premier cluster arrivent au début ; les approfondissements sécurité, observabilité, audit et upgrade reviennent lorsqu'un service IA réel permet d'en constater l'intérêt.

Week 5 n'est plus une unique grosse section. Ses labs éprouvés forment l'ossature du cours ; les longues manipulations sont scindées en expériences plus courtes, avec les mêmes configurations techniques de référence tant qu'une évolution n'a pas été revalidée.

BMaaS, VMaaS et KaaS ne sont plus des étapes obligatoires. Le contenu qui sert un scénario k0rdent AI documenté devient une extension spécialisée. Le reste quitte le parcours principal, sans destruction précipitée de l'historique.

### Faits observés dans le dépôt

Le README de Week 5 identifie déjà un parcours guidé 5.1 → 5.2 → 5.3 → 5.5 → 5.6, distinct des extensions. Son contrat de lab actuel repose sur un worker `g5.12xlarge` à quatre A10G. Le lab 5.5 contient notamment un passage d'une à quatre répliques et des étapes multi-GPU. Une variante à un GPU est donc une adaptation à tester, pas un simple remplacement du type d'instance. [S1–S3]

Le dépôt documente des réglages spécifiques k0s/containerd et une régression rencontrée avec une autre version de GPU Operator. La V2 doit préserver cette connaissance terrain et ne pas coupler refonte pédagogique et mise à jour générale des composants. [S4]

---

## 3. Une mission client fil rouge

### Le brief donné au participant

« Une équipe interne demande un service d'inférence privé. Une deuxième équipe doit exécuter des expérimentations et de petits entraînements. Les GPU sont limités. Vous devez fournir un accès contrôlé, une politique de partage compréhensible, des mesures de performance, une procédure de reprise et un déploiement reproductible avec k0rdent AI. »

Le brief évolue progressivement :

1. Un utilisateur obtient une première réponse.
2. Le contexte et la concurrence augmentent.
3. Une deuxième équipe réclame du GPU.
4. Un travail doit être distribué entre deux nœuds.
5. Les démarrages sont trop lents.
6. Une seconde plateforme doit être configurée de la même manière.
7. Un incident menace le service.
8. Le client attend une livraison autonome.

Les données sont synthétiques ou publiques et autorisées. Aucun document client ni secret réel n'est nécessaire.

### Le contrat k0rdent de chaque lab

Chaque fiche répond à quatre questions distinctes :

- Quel résultat utilisateur ou opérateur doit-on obtenir ?
- Qu'est-ce que k0rdent/k0rdent AI provisionne, distribue ou maintient ?
- Qu'est-ce que le runtime, le scheduler, le driver ou le matériel réalise réellement ?
- Quelle preuve montre que le résultat a été atteint ?

Une commande locale peut servir à comprendre ou diagnostiquer. La configuration persistante doit revenir dans le mécanisme déclaratif retenu pour le cours. Deux contrôleurs ne doivent pas gérer la même ressource sans responsabilité explicitement définie.

**Important :** k0rdent AI ne sera pas défini arbitrairement comme « k0rdent Enterprise + GPU Operator + vLLM ». Les composants, API, objets, licences, fonctions natives et intégrations réellement supportés seront établis à partir des sources produit fournies.

---

## 4. Le parcours commun : huit missions, aucune semaine imposée

Les missions ont des identifiants sémantiques stables. Leur ordre affiché peut évoluer sans renommer tous les labs. Leur nombre ne fixe ni leur durée ni un calendrier hebdomadaire.

### Mission 1 — De k0rdent AI à une première réponse

**Question :** comment passer d'un environnement vide à un service IA accessible et traçable ?

**Résultat :** une première requête réussit sur un petit modèle ; l'ingénieur sait expliquer le rôle des plans de management et de workload, du GPU et du runtime.

**Contenu réutilisé :** Week 1, labs 1.1, 1.2, 1.3 et 1.5 ; parties bootstrap de 5.1 et service minimal de 5.5.

**Capsules :** entraînement, fine-tuning et inférence ; tokens, paramètres et contexte ; API d'inférence ; rôle de k0rdent AI dans la chaîne ; CPU, RAM hôte et mémoire GPU.

**Manipulations :**

- Préparer le management plane, les accès et le provider selon la baseline validée.
- Provisionner un cluster de workload et un worker GPU choisi dans un profil qualifié.
- Déployer les composants GPU avec les valeurs spécifiques de la plateforme ; vérifier la disponibilité réelle du device, pas seulement le statut de la release Helm.
- Déployer le service d'inférence minimal ; effectuer une requête et retracer son exécution.
- Conserver la définition de l'environnement et une première preuve de bon fonctionnement.

**Incident :** distinguer un GPU non publié à Kubernetes d'un runtime GPU mal configuré.

**Critère de sortie :** démontrer le chemin de la requête jusqu'au GPU et pointer les ressources de management correspondantes. La première configuration d'accès reste privée ou restreinte ; un endpoint public non authentifié n'est pas une baseline acceptable.

**Matériel cible :** management CPU + un GPU ; variante produit exacte en attente de qualification.

### Mission 2 — Comprendre ce que consomme un modèle

**Question :** pourquoi un modèle qui semble tenir en mémoire peut-il poser problème en service ?

**Résultat :** établir un budget mémoire et une hypothèse de goulot d'étranglement à partir du workload.

**Contenu réutilisé :** théorie 5.2 et observations de 5.5 ; ajout d'un atelier de fondamentaux GPU.

**Capsules :** GPU et CUDA côté opérateur ; VRAM, HBM/GDDR, capacité et bande passante ; Tensor Cores ; FP32, FP16, BF16, FP8 et quantification comme choix matériels et logiciels ; poids, KV cache, buffers et mémoire du runtime ; prefill et decode.

**Manipulations :** inventorier le GPU réellement provisionné ; estimer la mémoire des poids ; relever la mémoire réservée et utilisée ; varier la longueur des entrées, la concurrence et les limites du serveur ; comparer prédiction et observation.

**Frontière de l'apprentissage :** les précisions ne sont pas toutes supposées disponibles sur tous les profils. HBM est enseignée, mais un GPU d'entrée de gamme équipé de GDDR ne devient pas un lab HBM.

**Incident :** une modification de contexte ou de paramètres de serving entraîne un refus, une pression mémoire ou une latence excessive. L'étudiant doit distinguer ces symptômes au lieu de tout nommer OOM.

**Critère de sortie :** expliquer la différence entre mémoire des poids et capacité de service ; proposer une modification justifiée puis la reporter dans la configuration de plateforme.

**Matériel cible :** un GPU.

### Mission 3 — Allouer et partager une ressource rare

**Question :** comment faire cohabiter deux équipes sans prétendre disposer de plus de GPU physiques ?

**Résultat :** différencier allocation, placement, admission, partage et isolation.

**Contenu réutilisé :** théorie 5.1, lab 5.3 KAI, parties pertinentes de 5.1 ; extension 5.19 pour MIG.

**Capsules :** device plugin et GPU entier ; DRA et ResourceClaims ; priorités et files ; gang scheduling ; time-slicing, MIG et vGPU ; différence entre quota et isolation de sécurité.

**Manipulations :** faire attendre un job faute de capacité ; observer puis modifier la politique de file du scheduler retenu ; utiliser des petits workloads pour expérimenter le partage ; comparer réservation et consommation réelle ; restaurer le profil initial avant les mesures de performance suivantes.

**DRA :** prévoir une expérience séparée avec une combinaison produit/driver/runtime/Kubernetes validée. Ne pas exposer deux fois un même GPU via deux méthodes concurrentes d'allocation. Si la branche produit cible ne supporte pas cette expérience, conserver son objectif conceptuel et l'extension isolée plutôt que casser la baseline.

**Choix de scheduler :** conserver le chemin KAI du dépôt pour la conception initiale. Ne pas imposer Kueue, Run:AI et KAI dans un empilement non validé. Les autres outils peuvent être comparés à titre architectural ; le parcours exécutable suit les sources k0rdent AI.

**Incident :** expliquer un job Pending à partir des événements, du quota, de l'allocation et des contraintes de placement.

**Critère de sortie :** prouver qui attend, pourquoi et comment il est admis ; ne pas confondre partage de temps et partition matérielle.

**Matériel cible :** un GPU pour les cas simples ; deux GPU pour démontrer certaines admissions/placements multi-worker ; matériel MIG spécialisé pour la manipulation MIG.

### Mission 4 — Faire travailler plusieurs GPU

**Question :** pourquoi ajouter un GPU ne garantit-il pas d'aller deux fois plus vite ?

**Résultat :** suivre le chemin des données, identifier les communications et comprendre une mesure de scaling.

**Contenu réutilisé :** théories 5.3 et 5.4 ; branches simplifiées des labs 5.15 et 5.16 ; lecture de topologie issue de 5.18.

**Capsules :** data, tensor, pipeline et expert parallelism ; AllReduce, AllGather, ReduceScatter ; NCCL ; PCIe, NUMA, NVLink/NVSwitch ; réseau inter-nœuds ; TCP, RDMA, InfiniBand, RoCE et EFA ; GPUDirect RDMA ; topologie et oversubscription.

**Manipulations du parcours commun :** provisionner temporairement deux workers mono-GPU ; lancer un petit entraînement distribué sur dataset synthétique ; exécuter un test de communication avec NCCL ; vérifier le transport dans les logs ; comparer temps par étape et débit sur une et deux ressources selon un protocole explicite.

**Protocole :** distinguer batch global fixe et batch par GPU fixe. Ne pas annoncer un gain attendu arbitraire ; le surcoût de communication est un résultat pédagogique valable.

**Incident :** modifier une configuration de rendez-vous ou d'interface dans un environnement isolé, avec délai d'expiration et restauration documentés. Distinguer problème de lancement, panne de communication et communication fonctionnelle mais lente.

**Référence matérielle :** analyser de véritables captures documentées de systèmes NVLink et de transports RDMA. Cette analyse ne valide pas une manipulation RDMA physique. EFA, RoCE et InfiniBand ne sont pas des noms interchangeables. Le support GPUDirect RDMA se vérifie séparément.

**Critère de sortie :** expliquer où circule le tenseur, quel transport est utilisé et quel type de parallélisme a été exécuté.

**Matériel cible :** deux GPU modestes, un par nœud, réservés à cette séquence ; accès mutualisé possible. La preuve pratique distribuée ne doit pas être remplacée par une simulation mono-GPU présentée comme équivalente.

### Mission 5 — Servir efficacement : inférence et données

**Question :** pourquoi le service ralentit-il ou met-il trop longtemps à démarrer alors que le modèle fonctionne ?

**Résultat :** mesurer séparément démarrage, latence, débit et alimentation en données ; identifier une amélioration utile au client.

**Contenu réutilisé :** suite du lab 5.5 ; nouveaux ateliers stockage et protocole de mesure.

**Capsules :** batching et continuous batching ; KV cache et cache de préfixes ; TTFT, latence par token et latence de bout en bout ; percentiles ; modèle de charge ; poids, datasets et checkpoints ; objet/S3, volume persistant, NVMe local et filesystem partagé ; GDS comme extension matérielle.

**Manipulations :** établir une baseline ; varier une dimension de charge à la fois ; comparer chargement à froid et depuis cache ; observer les lectures, le CPU, le réseau et le runtime ; rétablir le même état initial pour les répétitions ; enregistrer les résultats et les versions.

**Stockage :** ne pas transformer l'atelier en catalogue de vendeurs. Expliquer les rôles respectifs du stockage durable, de la zone de travail et du cache. Un microbenchmark local n'est pas un benchmark WEKA, VAST, DDN ou Lustre.

**Coût :** estimer le coût de la capacité allouée sur l'intervalle et le rapporter aux requêtes ou tokens effectivement servis sous l'objectif de qualité retenu. Documenter ce que le calcul inclut et exclut. Ne pas appeler cette estimation une facture client.

**Incident :** un cache vide rallonge le redémarrage ; une charge différente invalide une comparaison ; un service saturé attend sans nécessairement planter.

**Critère de sortie :** proposer une amélioration et démontrer qu'elle tient sous la même charge, avec les mêmes critères et la même qualité de service.

**Matériel cible :** un GPU ; un second uniquement pour l'expérience de scale-out réel.

### Mission 6 — Transformer le workload en service k0rdent AI

**Question :** comment livrer une capacité reproductible plutôt qu'un déploiement manuel isolé ?

**Résultat :** une définition versionnée de service et de plateforme peut être rejouée dans un autre environnement.

**Contenu réutilisé :** labs 5.2 et 5.12 ; lab 1.7 ; concepts de registre issus de 5.10 lorsque nécessaires.

**Capsules :** service de plateforme et workload utilisateur ; responsabilité des contrôleurs ; catalogue ; templates et valeurs ; credentials ; versions de modèles et de runtime ; propagation de configuration ; périmètre du produit.

**Manipulations :** transformer le service mesuré en configuration reproductible ; déployer le service via les mécanismes k0rdent AI documentés ; le reproduire sur une deuxième cible ; comparer l'état attendu à l'état observé ; publier une variante contrôlée ; revenir à la version antérieure.

**Multi-cluster :** un second cluster CPU peut prouver la propagation d'une politique compatible CPU, mais pas le service réel d'un modèle GPU sur deux sites. Pour prouver le serving sur deux cibles simultanées, réserver deux GPU ; pour une preuve de reproductibilité, la réutilisation séquentielle du GPU est acceptable et doit être annoncée comme telle.

**Incident :** une valeur de catalogue est incorrecte ou une dépendance de service manque. Remonter jusqu'à la source de configuration plutôt que modifier durablement les Pods à la main.

**Critère de sortie :** un autre ingénieur recrée la capacité à partir des livrables, sans étape cachée.

**Matériel cible :** un GPU réutilisé séquentiellement ; deux cibles GPU pour une preuve simultanée distincte.

### Mission 7 — Opérer, sécuriser et diagnostiquer

**Question :** que faire lorsque le service est lent, indisponible ou difficile à faire évoluer ?

**Résultat :** diagnostiquer une panne nouvelle, restaurer le service et remettre l'état déclaratif en cohérence.

**Contenu réutilisé :** labs 1.4, 1.6, 1.8, 1.9, 5.6 et 5.17 ; conservation des autres éléments utiles d'exploitation après revue.

**Capsules :** observabilité GPU, système et service ; DCGM ; KOF ; événements Kubernetes ; audit ; identité et autorisation ; isolation ; lifecycle ; rollback ; mesure d'usage et limites du chargeback.

**Manipulations :** compléter les tableaux de bord du service ; vérifier des refus d'accès ; capturer une trace d'audit ; préparer puis réaliser une évolution compatible ; simuler une panne limitée au lab ; recueillir les indices avant de changer la configuration ; réparer puis produire un mini compte rendu d'incident.

**Banque de pannes :** GPU non allocatable ; mauvais runtime ; job Pending ; modèle inaccessible ; cache non persistant ; problème de chargement de données ; configuration NCCL invalide ; mauvaise métrique de scaling ; cible de service mal sélectionnée.

**Règles :** injections limitées à l'environnement du participant ; restauration documentée ; pas de destruction de données client ; pas de panne globale sur un pool mutualisé ; jamais de mesure de réussite basée uniquement sur « GPU utilization > 70 % ».

**Critère de sortie :** diagnostic étayé, correction minimale, service rétabli, état déclaratif propre et dépenses résiduelles vérifiées.

**Matériel cible :** un GPU pour la majorité ; deux pour les incidents distribués.

### Mission 8 — Livrer une mission client sans mode d'emploi

**Question :** l'ingénieur peut-il transférer ses acquis à un scénario différent ?

**Résultat :** livraison de plateforme, justification d'architecture et procédure d'exploitation indépendantes d'une recette pas-à-pas.

**Brief :** deux équipes, une capacité GPU limitée, un service interactif et un job batch, une configuration déclarative, des accès contrôlés, un objectif de service calibré sur le matériel du lab et une enveloppe d'infrastructure.

**Livrables :** hypothèses de charge ; matrice de capacités ; configuration versionnée ; résultats de mesures ; runbook ; preuve de restauration ; estimation de coût ; limites explicites ; dossier de transfert.

**Épreuve :** le formateur modifie un paramètre ou introduit un incident inédit ; l'ingénieur l'analyse et défend ses décisions. Une comparaison avec une cible plus grande est demandée, mais aucune extrapolation linéaire non justifiée depuis le petit lab n'est acceptée.

**Validation :** la preuve matérielle, l'explication et la reproductibilité comptent. Une présentation convaincante ne compense pas un environnement non fonctionnel ; un environnement fonctionnel ne compense pas une incapacité à expliquer ses limites.

---

## 5. Traçabilité complète des contenus à conserver

### Week 1 : neuf labs conservés

| Source | Destination V2 | Traitement |
|---|---|---|
| 1.1 Provision k0rdent | Mission 1 | Conserver le bootstrap ; qualifier le pivot vers la distribution k0rdent AI cible. |
| 1.2 Explore UI | Missions 1 et 6 | Conserver ; suivre les objets du service IA plutôt qu'une visite sans scénario. |
| 1.3 AWS Provider | Mission 1 | Conserver ; intégrer profils matériels et préflight de prérequis. |
| 1.4 Production Configuration | Missions 1 et 7 | Garde-fous initiaux puis sécurisation et vérifications approfondies. |
| 1.5 Managed Cluster | Mission 1 | Conserver ; préparer le cluster destiné au workload IA. |
| 1.6 KOF | Missions 1, 5 et 7 | Observation minimale initiale ; approfondissement quand il existe une charge. |
| 1.7 Multi-Cluster Services | Mission 6 | Conserver ; applications à des politiques et services utiles à la plateforme IA. |
| 1.8 Upgrade | Mission 7 | Conserver ; évolution sous contrat de compatibilité, avec rollback et critères explicites. |
| 1.9 API Audit | Mission 7 | Conserver ; produire une preuve sur une action ou un refus pertinent. |

Les trois documents théoriques de Week 1 sont conservés comme références. Leurs sections sont consommées au moment opportun, sans exiger une lecture intégrale avant toute manipulation. [S5]

### Week 5 : dix-neuf labs préservés, avec de nouveaux statuts

| Source | Destination V2 | Arbitrage |
|---|---|---|
| 5.1 GPU Cluster Setup | Missions 1 et 3 | Réutiliser les réglages validés ; séparer bootstrap, runtime et scheduling. Créer une variante mono-GPU testée. |
| 5.2 Service Catalog | Mission 6 | Conserver et renforcer comme mécanisme d'industrialisation du fil rouge. |
| 5.3 KAI Scheduler | Mission 3 | Conserver ; calibrer les exercices de quotas et de jobs sur la capacité réellement disponible. |
| 5.4 Run:AI | Extension | Garder comme alternative sous licence ; pas un prérequis implicite. |
| 5.5 vLLM | Missions 1, 2 et 5 | Décomposer en premier service, budget mémoire et expérimentation de performance ; séparer scale-out et multi-GPU. |
| 5.6 Troubleshooting | Mission 7, incidents transverses | Conserver ; construire une banque de pannes à partir du contenu et des preuves existantes. |
| 5.7 Jupyter | Extension | Conserver ; ne pas imposer une plateforme notebook complète au parcours commun. |
| 5.8 Vector Database | Extension RAG | Conserver ; introduire brièvement le rôle architectural du retrieval dans les concepts. |
| 5.9 Kubeflow | Extension ML | Conserver ; ne pas installer toute une suite pour apprendre un unique entraînement distribué. |
| 5.10 MLflow | Concepts en Mission 6 + extension | Conserver le lab complet ; intégrer la traçabilité modèle/expérience dans le fil rouge selon le périmètre produit. |
| 5.11 FIPS | Extension conformité | Conserver ; ne pas confondre un réglage ou un lab avec une preuve globale de conformité. |
| 5.12 Cluster Templates | Mission 6 | Promouvoir dans le parcours principal : central pour apprendre l'orchestration reproductible. |
| 5.13 TensorRT-LLM | Extension optimisation | Conserver la branche spécifique ; ne pas introduire ses prérequis driver dans la baseline générale. |
| 5.14 Slurm | Extension HPC | Conserver sans en faire une étape pour tous. |
| 5.15 RDMA Multi-Cloud | Mission 4 + extension fabric | Créer un lab commun NCCL sur réseau ordinaire ; préserver le vrai lab RDMA séparément. |
| 5.16 Distributed Training | Mission 4 + extension | Ajouter une variante minimale à deux petits GPU ; préserver la version plus ambitieuse. |
| 5.17 Telemetry Export | Mission 7 | Conserver ; noyau de télémétrie opérationnelle obligatoire, export externe complet selon besoin. |
| 5.18 Topology/NVLink | Missions 2 et 4 + extension | Inventaire réel du petit lab ; analyse de captures ; validation matérielle spécialisée séparée. |
| 5.19 MIG | Mission 3, concept + extension matérielle | Conserver ; ne pas dépendre de MIG pour réussir le parcours commun. |

**Remplacer dans le chemin obligatoire n'est pas supprimer du dépôt.** Les extensions préservent l'investissement et permettent des spécialisations. Les nouveaux ateliers occupent la place libérée par les installations de suites non nécessaires.

Les cinq documents théoriques de Week 5 sont répartis : scheduling en Mission 3 ; inférence en Missions 1/2/5 ; communication et entraînement en Mission 4 ; plateformes ML comme carte des rôles, puis extensions. [S1]

---

## 6. Le matériel : une contrainte de conception et une preuve à qualifier

### Profils envisagés

| Profil de cours | Ressource réelle | Usages | Limite de la preuve |
|---|---|---|---|
| CPU | Management et cibles CPU | Bootstrap, catalogue, politique, sécurité, audit, propagation compatible CPU | Ne valide ni runtime GPU ni débit d'inférence GPU. |
| GPU-1 | Un GPU entier | Runtime, petit modèle, mémoire, sharing simple, observabilité, stockage | Ne valide ni scaling multi-GPU ni gang placement multi-worker complet. |
| GPU-2 | Deux workers mono-GPU | NCCL, petit entraînement distribué, scale-out réel | Ne valide pas NVLink, MIG, RDMA ou GPUDirect RDMA. |
| Fabric spécialisé | Matériel doté des capacités visées | MIG, NVLink/NVSwitch, RDMA, GDR, GDS selon profil | Chaque capacité doit être vérifiée séparément ; le nom de la famille GPU ne suffit pas. |

G4dn/T4, G5/A10G et G6/L4 constituent des candidats à la qualification des variantes légères. AWS documente leurs configurations mono-GPU, mais cela ne prouve ni la disponibilité instantanée dans un compte/AZ, ni la compatibilité de tous les dtypes, kernels et configurations du cours. [S6, S7]

Pour le parcours commun, utiliser un modèle suffisamment petit pour garder une marge mémoire sur le profil le plus contraint. Le nom du modèle, sa révision, sa licence, la précision, le runtime et le backend doivent être figés ensemble après exécution du test.

### Matrice de vérification avant publication

Chaque ligne de lab doit porter les champs suivants :

- Objectif et capacité matérielle requise.
- Version produit, Kubernetes/k0s, OS/AMI, driver, runtime, chart et image.
- Modèle, révision et précision.
- Type d'instance, région/AZ, nombre de GPU et mémoire effectivement visible.
- Résultat attendu et preuves recueillies.
- Date, auteur et résultat de validation.
- Durée active, durée facturable, coût observé, nettoyage et dépenses résiduelles.

Statuts : `proposé`, `documenté-compatible`, `exécuté`, `reproduit-par-un-autre-ingénieur`. Un lab n'est pas déclaré validé seulement parce que son README ou son manifeste a été relu.

### Quatre limites à enseigner explicitement

**MIG.** T4, A10G et L4 ne sont pas des cibles MIG. Le matériel supporté est listé par NVIDIA. Le concept reste obligatoire ; la pratique utilise un environnement compatible distinct. [S8]

**Partage.** Le time-slicing n'offre pas les mêmes garanties qu'une partition matérielle. NVIDIA précise aussi que DCGM Exporter ne permet pas d'associer ses métriques aux conteneurs lorsque le time-slicing du device plugin est activé. Une expérience de partage ne devient donc pas automatiquement un lab de facturation fiable par tenant. [S9]

**DRA.** La documentation GPU Operator consultée impose notamment un driver au moins 580 pour le chemin DRA présenté, ainsi que des conditions de runtime/CDI. Le dépôt conserve une baseline driver différente. Il faut une branche de compatibilité explicite, pas une mise à jour opportuniste du socle éprouvé. [S4, S10]

**Fabric.** EFA, support RDMA et GPUDirect RDMA sont des capacités distinctes dans les tableaux AWS. Un test NCCL passant sur le transport Socket ne démontre pas RDMA, même s'il constitue une vraie expérience distribuée utile. [S11, S12]

### Disponibilité et coût

Le préflight vérifie identité, IAM, quotas, types proposés, contraintes de template et profil matériel. Il ne prétend pas connaître avec certitude la capacité libre. AWS peut renvoyer `InsufficientInstanceCapacity` à la création ou au redémarrage. [S7]

Les changements autorisés de région, d'AZ et de type sont explicites. Il n'y a pas d'escalade silencieuse vers une instance chère. Une liste de fallback n'implique pas que k0rdent/CAPI réalise déjà nativement ce choix automatique ; le mécanisme de résolution doit être implémenté et testé séparément.

Le pool GPU-2 peut être mutualisé sur des créneaux. Les exercices destructifs ou de reconfiguration GPU nécessitent un accès exclusif. La réservation de GPU et les heures actives de formation sont suivies séparément. Le nettoyage inclut les ressources persistantes et réseau, pas seulement les VM.

---

## 7. Une pédagogie active, pas une suite de recettes

### La boucle de chaque expérience

**Prédire → manipuler → observer → expliquer → corriger → industrialiser.**

Avant de lancer une commande, le participant écrit une courte hypothèse. Après exécution, il conserve une preuve, compare avec son hypothèse et met à jour la définition de plateforme. La réussite d'une commande n'est pas une explication.

### Le guidage décroît

Au début, commandes et sorties attendues sont fournies, avec une explication de leur rôle. Ensuite, les manifestes comportent des décisions à prendre. Enfin, seuls le brief, les garde-fous et les critères de réussite sont donnés.

Les corrigés sont séparés des fiches participant. Ils expliquent pourquoi une solution fonctionne et quelles alternatives sont acceptables ; ils ne sont pas limités à un YAML final.

### La théorie reste disponible

Il ne s'agit pas de supprimer la profondeur. Chaque notion a trois niveaux : capsule nécessaire au lab, explication approfondie et référence officielle. Une carte « première rencontre / réutilisation / preuve finale » évite qu'un terme soit expliqué une fois puis oublié.

Exemple : le KV cache est introduit avec le premier modèle, mesuré en Mission 2, relié à la concurrence en Mission 5 puis mobilisé dans un incident de Mission 7.

### Les durées se mesurent

Cible de conception : environ trois quarts de manipulation, analyse de résultats et diagnostic. Les attentes de provisioning, téléchargements passifs et compilations de drivers ne sont pas comptabilisées comme temps hands-on. L'enveloppe totale et les niveaux d'approfondissement seront arbitrés à partir du temps réellement disponible pour les participants, puis recalibrés lors du pilote.

---

## 8. Évaluation et dossier de preuves

### Proposition de grille

| Dimension | Poids proposé |
|---|---:|
| Déploiement et orchestration reproductibles | 25 % |
| Explication des mécanismes IA et des choix de ressources | 20 % |
| Diagnostic et restauration | 25 % |
| Mesure de performance et coût interprétables | 15 % |
| Sécurité, lifecycle et qualité du transfert | 15 % |

Les erreurs critiques bloquent la validation, indépendamment de la moyenne : exposition involontaire d'un service sensible ; confusion entre simulation et preuve GPU ; absence de restauration ; secrets dans Git ; dépenses orphelines non identifiées ; état uniquement réparé à la main sans réconciliation déclarative.

Chaque participant remet une configuration, un manifeste de versions, ses observations, une décision d'architecture courte et une preuve d'exécution. Des questions d'explication et un incident inédit vérifient la compréhension.

Une qualification « fabric avancée » nécessite ses propres preuves sur matériel compatible ; le parcours commun ne la revendique pas par défaut.

---

## 9. Organisation cible du dépôt

```text
curriculum/
  README.md
  parcours.yaml
  missions/
    platform-bootstrap/
    gpu-systems/
    gpu-allocation/
    distributed-ai/
    inference-and-data/
    ai-service-delivery/
    operations/
    customer-engagement/
  extensions/
    bare-metal/
    virtualization/
    advanced-fabric/
    mig/
    ml-platforms/
    hpc/
    compliance/
  references/
    concepts/
    compatibility/
    evidence-packs/
  instructor/
    solutions/
    fault-injection/
    assessment/
    cohort-guide/
lab-infrastructure/
  profiles/
  preflight/
  validation/
  cleanup/
```

Les missions peuvent être affichées sous forme de modules dans la navigation. Les identifiants des labs restent sémantiques : `gpu-memory-pressure`, `nccl-two-workers`, `model-cold-start`, etc. Leur position ne fait pas partie de leur identité.

### Métadonnées proposées pour une fiche

Ce schéma est un format de contenu pour le cours, pas une API ni une ressource native k0rdent AI.

```yaml
id: gpu-memory-pressure
mission: gpu-systems
level: core
source_labs:
  - curriculum/week-5-ai-workloads/labs/lab-5.5-vllm-inference.md
prerequisites:
  - first-inference-endpoint
hardware_profile: gpu-1
practice_mode: live
validation_status: proposed
product_mapping_status: awaiting-k0rdent-ai-sources
outcomes:
  - distinguish-weight-memory-from-serving-capacity
  - explain-observed-behaviour
  - record-a-reproducible-configuration
evidence:
  - environment-manifest
  - load-description
  - runtime-and-device-observations
  - short-design-decision
cleanup_required: true
```

---

## 10. Implémentation sans perdre ce qui fonctionne

### Lot A — Figer la référence

Capturer le commit source, l'inventaire des labs et les preuves existantes. Distinguer les validations rapportées par l'auteur de celles reproduites pendant le pilote V2. Préserver les pins, réglages k0s, images et modèles associés à ces preuves.

### Lot B — Refondre la navigation

Créer les missions et leur graphe de prérequis ; fournir la table ancien → nouveau ; déplacer les fichiers avec conservation de l'historique ; mettre à jour les liens internes et les scripts. Éviter de changer à la fois chemins, versions et comportement.

### Lot C — Dériver une baseline matérielle légère

Tester le parcours « premier service → mémoire → partage simple → mesures → nettoyage » sur le premier profil mono-GPU retenu, puis sur un deuxième profil de secours. Conserver la variante quatre GPU du dépôt comme référence, sans prétendre que ses résultats ont déjà été reproduits sur une instance plus petite.

### Lot D — Ajouter les expériences manquantes

Écrire les ateliers mémoire, NCCL à deux workers, stockage/cache et protocole de benchmark. Relier chaque changement expérimental à une configuration de plateforme. Ajouter des sorties de validation et des diagnostics plutôt qu'un simple critère « Pod Running ».

### Lot E — Intégrer les sources produit k0rdent AI

Figer ce qui est natif, intégré, optionnel et hors périmètre. Qualifier l'installation, le lifecycle, les API, la gestion des modèles, l'identité, le scheduling et l'allocation GPU réellement supportés. Aucun nom d'objet ou mécanisme commercial ne sera inventé pour compléter le scénario.

### Lot F — Piloter et corriger

Faire exécuter le parcours par au moins un ingénieur qui n'a pas écrit les labs. Mesurer temps actif, blocages, interventions nécessaires, GPU-heures, coût résiduel et qualité des explications. Réviser le cours à partir de ces observations, pas seulement des impressions de son auteur.

---

## 11. Décisions encore ouvertes

Les contraintes déjà décidées ne sont pas à redemander : priorité à k0rdent AI, novices IA mais prérequis infra, majorité hands-on, fin des weeks, préservation de Week 1/5, prudence sur les GPU rares.

Restent à préciser pour produire la release exécutable : l'enveloppe de temps actif par participant ; le budget et la concurrence d'accès aux GPU ; la distribution/version k0rdent AI et ses sources ; le périmètre client à privilégier si une réduction du parcours est nécessaire ; la modalité de validation finale. Le format self-paced du dépôt constitue l'hypothèse initiale, sans exclure des revues de lab et de capstone.

---

## Références consultées

[S1] Mirantis-PS — Index Week 5 : https://github.com/Mirantis-PS/k0rdent-ai-training/blob/main/curriculum/week-5-ai-workloads/README.md

[S2] Mirantis-PS — Lab contract : https://github.com/Mirantis-PS/k0rdent-ai-training/blob/main/curriculum/week-5-ai-workloads/resources/lab-contract.md

[S3] Mirantis-PS — vLLM : https://github.com/Mirantis-PS/k0rdent-ai-training/blob/main/curriculum/week-5-ai-workloads/labs/lab-5.5-vllm-inference.md

[S4] Mirantis-PS — GPU bootstrap et compatibilité k0s : https://github.com/Mirantis-PS/k0rdent-ai-training/blob/main/curriculum/week-5-ai-workloads/labs/lab-5.1-gpu-cluster-setup.md

[S5] Mirantis-PS — Index Week 1 : https://github.com/Mirantis-PS/k0rdent-ai-training/blob/main/curriculum/week-1-foundations/README.md

[S6] AWS — Accelerated computing instance specifications : https://docs.aws.amazon.com/ec2/latest/instancetypes/ac.html

[S7] AWS — EC2 launch troubleshooting : https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/troubleshooting-launch.html

[S8] NVIDIA — MIG supported GPUs : https://docs.nvidia.com/datacenter/tesla/mig-user-guide/supported-gpus.html

[S9] NVIDIA — GPU time-slicing : https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html

[S10] NVIDIA — DRA driver, GPU Operator integration : https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/dra-intro-install.html

[S11] AWS — EFA, RDMA et GPUDirect capabilities : https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html

[S12] NVIDIA — NCCL environment and transport selection : https://github.com/NVIDIA/nccl/blob/master/docs/userguide/source/env.rst

[S13] vLLM — Parallelism and scaling : https://docs.vllm.ai/en/stable/serving/parallelism_scaling/

**Limite documentaire :** les pages `latest` et la branche `main` sont évolutives. La release du cours devra les remplacer par des versions ou commits identifiés lorsque disponibles.
