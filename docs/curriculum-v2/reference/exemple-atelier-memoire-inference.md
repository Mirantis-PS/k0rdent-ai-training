# Atelier V2 — « Les poids tiennent. Pourquoi le service attend-il ? »

**Mission :** Comprendre ce que consomme un modèle.

**Statut :** fiche pédagogique proposée, non exécutée pendant cette revue. Elle s'appuie sur un endpoint déjà déployé avec la baseline du cours. Le modèle, les versions, les commandes d'injection de charge et les plages de paramètres seront figés après validation du profil GPU. Aucun résultat chiffré ci-dessous n'est présenté comme une mesure réalisée.

## Brief participant

Votre équipe a déployé un petit modèle avec k0rdent AI. Une requête fonctionne. Une deuxième équipe vous demande maintenant d'ouvrir le service à plusieurs utilisateurs et d'accepter des questions plus longues.

Un collègue propose : « Les poids tiennent dans le GPU ; on peut ouvrir l'accès. »

Votre mission est de vérifier cette conclusion, de définir une configuration de service raisonnable et de la rendre reproductible.

## Ce que vous devrez prouver

À la fin de l'atelier, vous remettrez un budget mémoire, un tableau de mesures, une explication des limitations observées et une proposition de configuration. Vous devrez distinguer une limite de mémoire, une requête refusée, une attente dans le moteur et une latence élevée.

Le succès n'est pas de provoquer un OOM. Le succès est de prédire puis d'expliquer ce que fait le service, même s'il protège sa mémoire en attendant ou en refusant une requête.

## Prérequis et garde-fous

Utilisez le service d'inférence de la première mission et le GPU du profil validé. L'endpoint doit être privé ou contrôlé. Utilisez des prompts synthétiques, sans données client. Le GPU est réservé à cette expérience ; aucun autre participant ne doit subir les changements.

Conservez la configuration initiale et le mécanisme de restauration. Respectez le budget d'exécution et le plafond de concurrence fixé par le formateur. N'augmentez pas la taille d'instance pendant l'expérience. Une protection de service ou une erreur de configuration doit être analysée avant toute relance.

## Capsule 1 — Le modèle n'est pas tout le service

Les paramètres sont les nombres qui constituent les poids du modèle. La précision décrit leur représentation numérique. Pour un modèle dense hypothétique de trois milliards de paramètres stockés sur deux octets, l'estimation de base est :

`3 000 000 000 × 2 = 6 000 000 000 octets`, soit environ 6 Go décimaux.

Ce calcul porte uniquement sur les poids. Ce n'est ni la taille garantie du fichier, ni la quantité totale de mémoire utilisée par un moteur d'inférence, ni une preuve qu'une certaine concurrence est possible.

Le moteur utilise aussi des buffers et de la mémoire de travail. Le KV cache conserve des états utiles à la génération. Le contexte représente les tokens à prendre en compte. Le moteur peut réserver de la mémoire en amont : la mémoire réservée observée n'est donc pas nécessairement une mesure directe de la mémoire utile à une seule requête.

Les détails dépendent du modèle et du runtime. Vous devez les observer sur l'environnement du cours, pas appliquer une règle universelle.

## Expérience A — Écrire une prédiction avant la mesure

Sans modifier l'environnement, remplissez ce tableau :

| Question | Votre hypothèse | Justification |
|---|---|---|
| Quelle part de la mémoire sert aux poids ? | À renseigner | Paramètres et précision réellement utilisés. |
| La mémoire GPU visible est-elle identique à la RAM du worker ? | À renseigner | Sources d'observation distinctes. |
| Que changera une entrée plus longue ? | À renseigner | Hypothèse sur le traitement et les états conservés. |
| Que changera une concurrence plus élevée ? | À renseigner | Hypothèse sur les ressources et l'attente. |
| Le service doit-il nécessairement planter à saturation ? | À renseigner | Politique du moteur et limites de configuration. |

Enregistrez ensuite l'inventaire : type d'instance, GPU, mémoire visible, driver, image, modèle, révision, précision, arguments du moteur et configuration de déploiement. Retrouvez les ressources k0rdent qui ont conduit à cet état.

## Expérience B — Une requête, une baseline

Redémarrez le service seulement si le protocole validé l'exige. Distinguez la phase de chargement des poids et la phase de serving. Effectuez la chauffe définie par la fiche de validation ; elle ne doit pas être mélangée aux résultats retenus.

Envoyez un jeu de requêtes courtes prédéfini avec concurrence un. Conservez les tokens d'entrée et de sortie réellement traités, pas seulement la limite de sortie demandée. Utilisez le même jeu de données et le même paramétrage pour les comparaisons suivantes.

Relevez la mémoire GPU, les métriques du moteur, le nombre de requêtes actives et en attente, les erreurs, la latence de bout en bout et, lorsque le collecteur le mesure réellement, le délai jusqu'au premier token.

**Attention :** mesurer le temps d'un `curl` non streaming ne fournit pas à lui seul le délai jusqu'au premier token. Un fragment de flux n'est pas nécessairement un token. Le protocole de benchmark doit définir la mesure utilisée.

## Expérience C — Plus de concurrence, même entrée

Augmentez la concurrence par petits paliers autorisés, sans changer le modèle, la précision, les longueurs d'entrée ou les limites de sortie. Arrêtez la progression au plafond du lab, à la limite de service définie ou en cas d'erreurs répétées.

Pour chaque palier, conservez la même durée ou le même nombre de requêtes selon le protocole, puis répétez la mesure. Notez si les réponses se terminent normalement, attendent ou sont refusées.

| Palier | Tokens entrée/sortie observés | Requêtes réussies | Attente | Latence médiane / haute | Mémoire / cache | Interprétation |
|---|---|---|---|---|---|---|
| Référence | À mesurer | À mesurer | À mesurer | À mesurer | À mesurer | À expliquer |
| Palier suivant | À mesurer | À mesurer | À mesurer | À mesurer | À mesurer | À expliquer |
| Palier supérieur autorisé | À mesurer | À mesurer | À mesurer | À mesurer | À mesurer | À expliquer |

Avant d'expliquer un écart, vérifiez que le générateur de charge n'est pas lui-même la limite.

## Expérience D — Plus de contexte, concurrence fixe

Revenez à la concurrence de référence. Remplacez les entrées par un jeu plus long autorisé, avec un nombre de tokens vérifié. Ne modifiez pas simultanément la concurrence et la longueur d'entrée.

Comparez le temps avant génération, la durée de réponse, les métriques de cache et les éventuels refus. Un refus pour longueur excessive n'est pas la même panne qu'un OOM. Une mémoire déjà préallouée peut rester presque constante alors que le service atteint une autre limite.

## Expérience E — Une amélioration, pas dix

Choisissez une seule modification pertinente : limite de contexte, concurrence admise, configuration du moteur, politique de service ou autre paramètre supporté par la version du cours. Expliquez la contrepartie pour les utilisateurs.

Avant application, vérifiez où se situe l'autorité déclarative. Faites la modification dans le template ou les valeurs pilotées par le mécanisme k0rdent AI retenu, puis observez son déploiement. N'effectuez pas une correction persistante dans un Pod ou un objet rendu si un contrôleur va la remplacer.

Rejouez exactement la charge de comparaison. Une configuration n'est pas meilleure parce qu'elle sert des requêtes plus faciles ou plus courtes.

## Débrief participant

Rédigez cinq paragraphes courts :

1. Ce que vous aviez prévu et ce que vous avez réellement observé.
2. Pourquoi la taille des poids ne suffit pas pour dimensionner un service.
3. La ressource ou la politique qui a limité votre expérience, et les preuves qui soutiennent ce diagnostic.
4. La modification retenue, sa contrepartie et sa représentation dans k0rdent AI.
5. Ce que vous ne pouvez pas conclure : performance sur un autre GPU, capacité de production, qualité d'un modèle quantifié non évaluée, ou coût total hors périmètre.

## Critères d'acceptation

Le dossier contient la configuration initiale, la description reproductible des charges, les mesures, la décision et la configuration finale. Un autre ingénieur peut distinguer les observations des hypothèses. La conclusion ne promet pas une concurrence universelle à partir d'un seul test.

La configuration conservée est documentée. Les données de l'expérience sont sauvegardées dans le dossier de preuves. Les charges sont arrêtées. Les ressources facturables restantes sont identifiées.

## Notes formateur — à retirer de la version participant

Ne fournissez pas de résultat attendu du type « la mémoire augmente de X % ». L'allocation et les protections dépendent du moteur. Les critères portent sur la qualité de l'expérience et l'explication.

Au premier passage, fournissez le protocole de mesure. Lors d'une réutilisation ultérieure, donnez seulement la question client et demandez au participant de proposer lui-même le protocole. Au capstone, changez le modèle de charge ou les contraintes plutôt que reproduire la même recette.

L'erreur pédagogique à éviter est de récompenser uniquement celui qui a fait planter le service. Une personne capable d'expliquer un refus propre et une file d'attente peut avoir mieux compris le système.

## Références de préparation

Le socle de serving et ses commandes proviennent du lab existant :
https://github.com/Mirantis-PS/k0rdent-ai-training/blob/main/curriculum/week-5-ai-workloads/labs/lab-5.5-vllm-inference.md

Les principes de déploiement parallèle doivent être confrontés à la documentation de la version de vLLM utilisée :
https://docs.vllm.ai/en/stable/serving/parallelism_scaling/

Les API, paramètres et mécanismes de lifecycle propres à k0rdent AI devront être associés aux sources produit fournies avant de déclarer cet atelier exécutable.
