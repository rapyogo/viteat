# Plan : Agent IA dans l'app client, préférences de notification et profil de personnalisation

Date : 09/10/2026. Statut : **enregistré pour plus tard, non commencé.** Demandé par l'utilisateur pendant la recette du lot 2 de fluidité.

## Demande

1. Dans « Mon compte », vérifier que les options de notification déjà gérées par le backend sont présentes.
2. Ajouter au profil les informations qui personnalisent l'expérience et nourrissent l'IA :
   - préférences alimentaires ;
   - allergies ;
   - objectifs de santé.
3. Ajouter une section **« Agent IA »** :
   - une conversation dans le même style que WhatsApp ;
   - liée automatiquement à la session de l'utilisateur connecté (pas de code de liaison, contrairement à WhatsApp).

## État constaté le 09/10/2026

| Sujet | Backend (`Order Tracking Firebase Function/functions`) | App client (`customer-clean`) |
|---|---|---|
| Notifications | `users.notificationPrefs.announcements` (booléen) : annonces de nouveaux restaurants. Lu par `products/restaurant_launch/index.js` (l. 268). Synchronisé avec STOP/START sur WhatsApp (`whatsapp/marketing.js`). Les règles Firestore permettent au titulaire de le modifier (`test/rules/vitrine_annonces.rules.test.js:110`). | **Absent.** Aucun écran ne lit ni n'écrit `notificationPrefs`. |
| Allergies et préférences | Le bot WhatsApp les enregistre via l'outil `update_customer_notes` (`whatsapp/gemini.js:195-215`), mais dans **`whatsappSessions/{sessionId}`** (champs `allergies`, `preferences`, `conversationSummary`, chacun plafonné à 8 entrées). Elles sont attachées à la conversation WhatsApp, pas au compte. | **Absent.** |
| Conversation IA | Pipeline Gemini, avec repli sur Anthropic et DeepSeek (`whatsapp/ai`, `whatsapp/pipeline.js`), et outils de lecture du catalogue réel. Un simulateur existe (`simulateWhatsAppBot`, `whatsapp/simulator.js`), mais il est réservé à l'admin, en lecture seule, sans état. | Écran « Lier WhatsApp » uniquement. |

## Conception proposée

### A. Notifications (petit, à faire en premier, environ 1 h)
- **Profil** : nouvelle carte « Notifications » avec un interrupteur « Nouveaux restaurants et annonces ». Il écrit `notificationPrefs.announcements` par `update` (la règle existe déjà). Valeur par défaut affichée : activé si le champ est absent, comme le backend.
- **Modèle** : lecture tolérante dans `UserModel` (un map `notificationPrefs`, sans planter si le champ manque).
- **Plus tard**, si le backend en ajoute : notifications de commande (toujours actives, pas d'interrupteur) et promotions.

### B. Profil de personnalisation (moyen)
- **Données sur le compte** (source unique pour l'app, le bot WhatsApp et l'Agent IA) : `users/{uid}.tastePrefs` = `{ dietary: [], allergies: [], healthGoals: [], dislikes: [], spiceLevel, budget, updatedAt }`.
- **Écran « Mes préférences »** dans le profil :
  - puces à choix multiple (végétarien, halal, sans porc, léger, moins de sucre, protéiné…) ;
  - champ libre pour les allergies.
- **Mention claire** sous les allergies : « Viteat ne garantit pas l'absence d'allergènes : confirmez avec le restaurant ». Le catalogue n'a pas de données d'allergènes vérifiées, et le prompt du bot le dit déjà.
- **Backend** : `update_customer_notes` écrit aussi dans `users/{viteatUserId}.tastePrefs` quand le numéro est lié, et le pipeline lit `tastePrefs` dans son contexte. À faire dans le dépôt des fonctions, avec ses tests (`node --test test/whatsapp/*.test.js`).
- **Règles Firestore** : le titulaire ne modifie que `tastePrefs` et `notificationPrefs`. Ajouter un test de règles.

### C. Section « Agent IA » (gros chantier, 2 à 3 sessions)
- **Backend** : nouvelle callable `v1_customerAgentMessage`, ou un trigger sur `customerAgentThreads/{uid}/messages`.
  - Authentification Firebase obligatoire, avec un `uid` pris dans `request.auth` (jamais un identifiant envoyé par le client).
  - Réutilise le pipeline du bot (même prompt, mêmes outils de catalogue, même chaîne de fournisseurs IA), avec un contexte « canal app » : pas d'envoi Meta, réponse renvoyée.
  - Historique persistant dans `customerAgentThreads/{uid}`.
  - Limites : quota de messages par jour et par utilisateur, et taille maximale, contre l'abus et le coût.
  - Outils autorisés au départ : recherche de plats et de restaurants, suivi de commande, préférences. **Aucune commande ni paiement par l'agent en V1** : il propose, et l'utilisateur ouvre la fiche dans l'app.
  - Passage à un humain : réutiliser `requestHumanSupport` (`supportTickets`).
- **App** :
  - onglet ou entrée « Agent IA » dans le profil, avec un écran de discussion façon WhatsApp (bulles, horodatage, indicateur « en train d'écrire », envoi désactivé hors ligne) ;
  - réponses contenant des cartes de plats ou de restaurants cliquables, qui ouvrent la fiche existante ;
  - historique chargé page par page, plus récent en premier.
- **Sécurité et vie privée** :
  - aucune donnée de paiement ni de wallet dans le contexte IA ;
  - préférences et allergies, seulement si présentes ;
  - possibilité d'effacer l'historique.

## Ordre conseillé
1. A (notifications) : petit, utile tout de suite, aucun risque.
2. B côté app, puis côté backend (le bot lit et écrit le profil).
3. C, avec une spécification validée par l'utilisateur avant le code (coût IA, quotas, outils autorisés).

## Contraintes à respecter
- Aucune modification de FlexPay, du wallet ni du checkout.
- Ne fusionner ni déployer : les déploiements en production sont lancés par l'utilisateur.
- Commits en français, un par point, `flutter analyze` après chaque point.
