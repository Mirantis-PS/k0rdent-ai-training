# Transmission complète à Codex — k0rdent AI Training V2

**Préparé le 14 octobre 2026.** Ce dossier consolide les décisions de la conversation et les documents de conception déjà créés. Il ne contient aucun outil de migration et ne prouve aucune modification du dépôt. L’état réel du dépôt doit être inspecté dans le projet Codex.

## Pourquoi ce dossier

Le dernier prompt était suffisant pour lancer une réorganisation conservatrice, mais il excluait explicitement les nouveaux fondamentaux IA, les adaptations GPU et les nouvelles procédures produit. Il ne constituait donc pas une spécification complète de la V2.

Ce dossier distingue **l’objectif complet**, **le travail actuellement autorisé** et **les preuves requises pour annoncer chaque étape terminée**. La conservation du contexte n’est pas une garantie d’exécution parfaite ; les résultats devront être vérifiés.

## Utilisation dans le projet local

Donner ce dossier à Codex, à côté du clone ou sous forme de fichiers joints lisibles. Lui transmettre le contenu de `START-PROMPT.txt`. Les chemins `docs/curriculum-v2/` sont destinés au dépôt, mais Codex doit d’abord inspecter son état et préserver les modifications existantes. Ne pas écraser un répertoire ou un fichier homonyme.

`AGENTS-SECTION.md` est une section à intégrer au fichier d’instructions existant, pas un remplacement de celui-ci. Les règles propres au dépôt restent applicables. Les documents de référence français sont conservés comme archives de conception ; les nouveaux supports pédagogiques du dépôt sont en anglais.

## Contenu et ordre de lecture

| Document | Fonction |
|---|---|
| `docs/curriculum-v2/MASTER-SPEC.md` | Décisions, périmètre complet, pédagogie, modules, matériel et critères globaux. |
| `docs/curriculum-v2/IMPLEMENTATION-PLAN.md` | Lots distincts, autorisations, livrables et tests de sortie. |
| `docs/curriculum-v2/COVERAGE-MATRIX.md` | Chaque notion IA et exigence a une destination et une preuve attendue. |
| `docs/curriculum-v2/PRESERVATION-MAP.md` | Conservation des 28 repères historiques Weeks 1/5 et inventaire de tous les autres fichiers. |
| `docs/curriculum-v2/STATUS.md` | État initial explicite : rien n’est déclaré exécuté ou validé sur le dépôt. |
| `docs/curriculum-v2/reference/` | Les deux documents pédagogiques antérieurs, conservés sans modification. |
| `AGENTS-SECTION.md` | Règles courtes et pointeurs vers les documents persistants. |
| `START-PROMPT.txt` | Instruction de démarrage à transmettre à Codex. |

## Autorisation actuelle

Exécuter **P0 et P1** : inspection, branche, inventaire, réorganisation, liens, navigation et conservation détaillée du backlog V2. Les autres lots décrivent la cible intégrale ; leur présence n’autorise pas implicitement de nouvelles procédures produit, une mise à niveau du runtime, une dépense cloud, un push ou une fusion.

Pour poursuivre ensuite, le propriétaire peut explicitement autoriser P2 (enrichissement pédagogique), puis les lots produit et matériel. Un lot différé doit conserver toutes ses exigences, son statut et sa raison de report ; il ne disparaît pas dans un simple « à voir plus tard ».

## Ce que ce dossier ne remplace pas

Le checkout réel, les sources k0rdent AI à fournir, la documentation officielle des versions retenues, un compte et des quotas AWS autorisés, les essais GPU et la relecture humaine. Les constats techniques des documents antérieurs étaient datés : ils doivent être revalidés avant emploi opérationnel.

## Références sur l’organisation du travail Codex

La documentation OpenAI décrit les instructions de projet `AGENTS.md`. Elle recommande aussi, pour les travaux longs, de séparer spécification, plan à jalons, consignes d’exécution et journal de progression avec vérifications. Ces ressources expliquent l’organisation du dossier, pas une garantie d’exécution.

- https://learn.chatgpt.com/docs/agent-configuration/agents-md
- https://developers.openai.com/blog/run-long-horizon-tasks-with-codex
