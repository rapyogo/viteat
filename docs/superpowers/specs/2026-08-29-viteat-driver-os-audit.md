# Viteat Driver OS — audit de l'existant et matrice d'impact

**Date :** 2026-08-29
**Statut :** audit, en attente de validation (étapes 1 à 6 du §72 du brief)
**Périmètre :** `rapyogo-2bccd` (production), app `driver`, `Admin Panel`, Cloud Functions, nouveau `Drive panel/`
**Suite :** aucun changement structurel avant validation de ce document (§72 étape 8)

---

## 1. Ce qui a été décidé avant l'audit

| Question | Décision |
|---|---|
| Nature de `Drive panel/` | **Espace web du livreur lui-même**, pas un back-office. Le livreur s'y connecte et y fait plus que dans l'app mobile. |
| Administration du réseau | Reste dans l'`Admin Panel`, où les vues manquantes seront ajoutées. |
| Siège des règles métier | **Cloud Functions**. Ni le mobile, ni le navigateur, ni Laravel ne décident. |
| Connexion du livreur | Firebase Auth — téléphone/OTP **et** email/mot de passe au choix. |
| Candidature | Libre : n'importe qui peut déposer un dossier depuis le web. |
| Stratégie face à la production | **Collections neuves, existant intact.** Pas de projet de staging. |
| Premier chantier | Socle du portail + parcours candidature → activation. |

**Écart assumé avec le brief.** Le §69 demande un environnement de staging avec 30 livreurs fictifs.
La décision prise est de ne pas en créer et de travailler par collections neuves sur la production.
C'est sans risque tant qu'on n'écrit que dans des collections neuves ; ça cesse de l'être au
chantier « courses » (§13) et au chantier « argent » (§18), qui touchent des collections vivantes.
À rouvrir à ce moment-là.

---

## 2. LE point bloquant : la base est publiquement ouverte en écriture

Les règles de sécurité déployées sur `rapyogo-2bccd` sont, au 2026-08-29 :

```
match /{document=**} { allow read, write: if true; }
```

Release publiée le **2025-05-29**, toujours active. La clé API Firebase est extractible de l'APK
livreur. **N'importe qui sur Internet peut aujourd'hui écrire n'importe quel document.**

### Pourquoi cela commande tout le reste

Le brief repose sur une règle unique, énoncée au §70 : `BACKEND = SOURCE DE VÉRITÉ`. Elle est
répétée aux §14, §21, §27, §42 et §50. Or, tant que les règles sont ouvertes, elle est
**techniquement irréalisable**. Un livreur muni de la clé de son propre APK peut, depuis une console
de navigateur :

| Écriture | Conséquence |
|---|---|
| `driver_program/{soi}.level = 3` | S'auto-promeut Ambassadeur |
| `driver_program/{soi}.score = 100` | S'attribue le score maximal |
| `driver_ledger/{nouveau}` | Se crédite un montant arbitraire |
| `driver_program/{soi}.status = ACTIVE` | Contourne formation, test et certification |

Placer les règles dans des Cloud Functions ne change rien à cela : les Functions deviennent une porte
parmi deux, et la seconde est grande ouverte. **Une Cloud Function ne protège une donnée que si
l'écriture directe sur cette donnée est interdite par ailleurs.**

### Conséquence sur l'ordre des chantiers

La spec `2026-08-29-securisation-regles-firestore-design.md` traite exactement ce problème et est
déjà rédigée — statut « en attente de relecture », **non implémentée**. Elle devient un **prérequis
dur** du Driver OS, pas un chantier parallèle.

Son palier 1 (fermer l'accès anonyme) ne suffit pas ici : l'inscription cliente étant libre, un
compte s'obtient en trente secondes et retrouve les droits d'aujourd'hui. **C'est le palier 2
— règles par rôle et par collection — qui est le prérequis réel.**

Un point favorable : les collections du Driver OS étant **neuves**, leurs règles peuvent être
écrites restrictives dès leur création, sans le risque de casser un flux existant qui pèse sur les
33 collections actuelles. On peut donc avancer sur le portail livreur en parallèle du chantier
sécurité, à condition de ne jamais considérer une donnée comme fiable avant le palier 2.

> **Correction du 2026-08-31.** Ce paragraphe était incomplet et sa conclusion pratique était
> fausse. Firestore n'applique pas « la règle la plus spécifique gagne » : il réunit toutes les
> règles qui couvrent un chemin par un **OU logique**, et un seul `allow` suffit à autoriser
> l'accès. Le joker `match /{document=**} { allow read, write: if true; }` actuellement déployé
> couvre donc aussi les collections neuves et rendrait décorative toute règle restrictive écrite
> à côté. Vérifié sur reproduction isolée en émulateur.
>
> Écrire des règles strictes sur les collections neuves exige donc de **borner le joker** pour
> qu'il les exclue nommément — ce que fait désormais le plan 1A. Toute nouvelle collection
> `driver_*` doit être ajoutée à cette liste d'exclusion, sans quoi elle naît publiquement
> écrivable.

---

## 3. Inventaire de l'existant

### 3.1 Où vivent réellement les données

| Support | Contenu | Volume |
|---|---|---|
| **Firestore `rapyogo-2bccd`** | **La totalité du métier** | 33 collections déclarées, 19 utilisées par l'app livreur |
| **MySQL `monsite3`** (Admin Panel) | Authentification et RBAC des administrateurs | **7 tables** |
| **MySQL `monsite2`** (Restaurant Panel) | Authentification des restaurateurs | **6 tables** |
| **MySQL `monsite1`** (Website Panel) | Authentification | **6 tables** |

**Il existe bien trois bases SQL, une par panel.** Vérifié le 2026-08-31 non sur les dumps
d'installation mais sur le répertoire de données MySQL vivant, `C:\xampp\xampp\mysql\data`
(le serveur était arrêté ; chaque base y est un répertoire, chaque table un fichier).

Leur contenu, exhaustivement :

- `monsite3` : `failed_jobs`, `migrations`, `password_resets`, `permissions`,
  `personal_access_tokens`, `role`, `users`
- `monsite2` et `monsite1` : `failed_jobs`, `migrations`, `password_resets`,
  `personal_access_tokens`, `users`, `vendor_users`

Ce sont, à la table près, la plomberie de Laravel plus les comptes de connexion et les rôles.
**Aucune donnée métier** : ni commande, ni restaurant, ni plat, ni livreur, ni paiement. Le
métier vit intégralement dans Firestore, et ces trois bases ne servent qu'à ouvrir une session
dans un panel.

**Conséquence sur le §67.** Le brief demande une trentaine de tables (`drivers`, `deliveries`,
`financial_transactions`, `kpis`…). Il n'existe aucune base relationnelle métier où les créer.
Les créer en MySQL fabriquerait une seconde source de vérité à synchroniser avec Firestore — la
faute d'architecture la plus coûteuse possible ici. **Ces entités seront des collections Firestore.**
Le §67 le prévoit lui-même : « adapter les noms à l'architecture existante ».

### 3.2 Collections Firestore utilisées par l'app livreur

| Collection | Contenu réel |
|---|---|
| `users` | Profil livreur (`role: "driver"`) : identité, `wallet_amount`, `zoneId`, `location`, `rotation`, `userBankDetails`, `active`, `isActive`, `isDocumentVerify`, `orderRequestData`, `inProgressOrderID`, `fcmToken` |
| `documents` | **Catalogue** des types de pièces : `title`, `frontSide`, `backSide`, `expireAt`, `enable` |
| `documents_verify` | **Pièces déposées** : `frontImage`, `backImage`, `status`, `documentId` |
| `wallet` | Mouvements : `user_id`, `amount`, `isTopUp`, `order_id`, `payment_status`, `date`, `note` |
| `driver_payouts`, `payouts`, `withdraw_method` | Versements et moyens de retrait |
| `referral` | `referralCode`, `referralBy` — rien d'autre |
| `zone` | `name`, `area` (polygone), `latitude`, `longitude`, `publish` |
| `restaurant_orders` | Commandes, 10 statuts |
| `settings` | Configuration des 4 applications, dont `driverNearBy` |
| `chat`, `notifications`, `dynamic_notification`, `email_templates`, `tax`, `currencies`, `on_boarding` | Support, notifications, référentiels |

### 3.2b Volumétrie réelle des livreurs (relevé du 2026-08-29)

| Mesure | Nombre |
|---|---|
| `users` avec `role == "driver"` | **383** |
| dont `isActive == true` | **8** |
| dont `isDocumentVerify == true` | 12 |
| dont `fcmToken` présent | 370 |
| dont `zoneId` renseigné | **42** |
| dont coordonnées bancaires | 138 |

L'objectif de 30 livreurs du brief est un objectif **d'activation**, pas un effectif. 383 comptes
sont ouverts, 8 fonctionnent.

`deliveryDispatch` exige `driver.zoneId == zone de la commande` : **341 comptes n'ont aucune zone**
et ne peuvent structurellement recevoir aucune course. C'est la première explication de l'écart
entre 383 inscrits et 8 actifs.

Le catalogue `documents` contient cinq types hérités du template indien (`RC Book`,
`FSSAI Certificate`, `Driving License`, `ID Proof`, `Autorisation d'ouverture`), aucun avec
`expireAt` renseigné. La collection `zone` contient sept entrées dont `Worldwide` et `World Wide`
en doublon. Les deux sont à redéfinir pour la RDC — décision d'exploitation, pas technique.

### 3.3 Cloud Functions déployées

| Fonction | Rôle | Origine |
|---|---|---|
| `deliveryDispatch` | Attribution des commandes aux livreurs | Connue |
| `deleteUser` | Suppression de compte Auth | Connue |
| `initiateMobileMoneyPayment`, `checkMobileMoneyStatus`, `flexPayCallback` | FlexPay Mobile Money | Connue, **LIVE, jamais testée en réel** |
| `helloWorld`, `sendNewOrderNotification` | — | **Inconnue.** Doublon possible avec `deliveryDispatch`. Ne pas toucher sans investigation. |

### 3.4 Ce que fait réellement `deliveryDispatch`

Déclenché sur `restaurant_orders`. Aux statuts `Order Accepted` ou `Driver Rejected`, il cherche un
livreur en parcourant `users` où `role == "driver"`, et retient le **premier** qui satisfait :
`fcmToken` non vide, `zoneId` égal à la zone de la commande, `vendorID` vide, distance au restaurant
inférieure au rayon, absent de la liste des refus, et — si `singleOrderReceive` est actif — sans
commande en cours.

Configuration lue dans `settings/driverNearBy` : `driverRadios`, `distanceType`,
`driverOrderAcceptRejectDuration`, `orderAutoCancelDuration`, `singleOrderReceive`,
`minimumDepositToRideAccept`.

**Il n'existe donc aucune notion de disponibilité déclarée.** Un livreur est « disponible » s'il a un
jeton FCM et pas de commande en cours — exactement ce que le §12 interdit.

### 3.5 Statuts de commande existants

`Order Placed` → `Order Accepted` / `Order Rejected` → `Driver Pending` → `Driver Accepted` /
`Driver Rejected` → `Order Shipped` → `In Transit` → `Order Completed`, plus `Order Cancelled`.

Dix états, en chaînes de caractères anglaises, lus et écrits par **quatre applications** et par
`deliveryDispatch`. Le §13 en demande quatorze, plus fins.

### 3.6 Écrans de l'app livreur

17 répertoires : authentification, tableau de bord, accueil, liste de commandes, portefeuille,
méthodes de retrait, profil, mot de passe, langue, chat, aide, vérification, conditions,
intégration, splash, maintenance.

Le §51 en demande 30.

### 3.7 RBAC

Les tables `role` et `permissions` existent, et le middleware `permission:<permission>,<route>` est
appliqué sur toutes les routes de l'`Admin Panel`. **Mais la base ne contient qu'un seul rôle :
« Super Administrator ».** Le mécanisme du §39 est présent et inexploité.

### 3.8 API

`Admin Panel/routes/api.php` contient **une seule route**. Il n'existe aucune API au sens du §66.

---

## 4. Matrice d'impact

Légende : **E** existant et suffisant · **M** à modifier ou étendre · **C** à créer · **R** à risque

| § | Domaine | État réel | Verdict |
|---|---|---|---|
| 2, 22-26 | Niveaux 1/2/3 et progression | Rien | **C** |
| 3 | Workflow candidature → activation | 3 booléens (`active`, `isActive`, `isDocumentVerify`) | **C** |
| 4 | Profil livreur | `users` couvre ~40 % des champs demandés | **M** |
| 5 | ID `VT-LVR-` | Rien | **C** |
| 6 | QR code | Rien | **C** |
| 7 | Documents | `documents` + `documents_verify` existent | **M** — manquent les 4 statuts, l'expiration effective, la version, le validateur, l'historique, l'alerte avant échéance |
| 8 | Formation | Rien | **C** |
| 9 | Certification | Rien | **C** |
| 10 | Signature électronique | Rien | **C** |
| 11 | Activation par checklist | `isActive` posé à la main | **M · R** — l'app livreur lit ce champ ; le redéfinir change le comportement de livreurs actifs |
| 12 | Disponibilité horodatée | Déduite du jeton FCM | **C · R** — touche `deliveryDispatch` |
| 13 | Cycle de course (14 états) | 10 états, en chaînes | **M · R majeur** — 4 apps + 1 Function lisent ces chaînes |
| 14 | Rémunération confirmée au backend | Rien | **C** |
| 15, 40 | Moteur tarifaire versionné | Calcul dans l'app cliente + `settings` | **C · R** |
| 16 | Partage 80/20 | `adminCommission` dans `settings` | **M** |
| 17, 18 | Ledger immuable | `wallet` : journal simple et **modifiable** | **C** — nouveau ledger ; `wallet` conservé |
| 19 | Paiement instantané, 5 statuts | `driver_payouts`, `withdraw_method`, FlexPay | **M** |
| 20 | KPI | Rien | **C** |
| 21 | Score Viteat /100 | Rien | **C** |
| 27-30 | Points, badges, récompenses, challenges | Rien | **C** |
| 31 | Classement | Rien | **C** |
| 32 | Parrainage | `referral` : code + parrain, sans condition ni récompense | **M** |
| 33 | Support par tickets | `chat` + `SupportHistoryController` | **M** |
| 34, 35 | Notifications et centre de notifications | FCM opérationnel mais fragile (normes N1/N2/N3) | **M** |
| 36 | Timeline du livreur | Rien | **C** |
| 37 | Audit log | Rien | **C** |
| 38 | Administration des livreurs | `DriverController` : liste, édition, vue, documents, chat | **M** |
| 39 | RBAC, 6 rôles | Mécanisme complet, **1 seul rôle en base** | **M** — peupler, pas construire |
| 41 | Budgets | Rien | **C** |
| 42 | Moteur de bonus | Rien | **C** |
| 43 | Incidents | Rien | **C** |
| 44 | Détection de fraude | Rien | **C** |
| 45 | Géolocalisation | `location`, `rotation`, `geofirestore` | **E** |
| 46 | Zones | `zone` : polygone + publication | **M** — ni tarif, ni priorité, ni capacité |
| 47 | Attribution intelligente | `deliveryDispatch` : rayon, zone, charge | **M · R majeur** — tourne en production |
| 48 | Passage à l'échelle | 192 index Firestore déployés | **M** — ni pagination, ni file asynchrone |
| 49 | Sécurité | Firebase Auth + OTP présents ; **règles ouvertes** | **C · R critique** — voir §2 |
| 50 | Mode hors ligne | Cache Firestore par défaut seulement | **C** |
| 51 | 30 écrans livreur | 17 écrans | **M** — 13 à créer, répartis entre mobile et web |
| 66 | API versionnée | 1 route | **C** |
| 69 | Staging | Inexistant | **écart assumé**, voir §1 |

### À supprimer

**Rien.** Aucune fonctionnalité existante ne doit disparaître (§73).

Deux éléments seulement sont à *investiguer* avant de trancher : les Cloud Functions `helloWorld` et
`sendNewOrderNotification`, d'origine inconnue, dont la seconde fait peut-être doublon avec
`deliveryDispatch`. Elles restent déployées et intouchées d'ici là.

---

## 5. Trois tensions entre le brief et le terrain

**Le §66 demande une API REST versionnée** (`/api/v1/drivers`…). L'écosystème est Firestore-natif :
les deux apps Flutter et les 210 vues web parlent directement à Firestore, et aucune API n'existe.
Construire une API REST imposerait de recâbler l'app livreur en profondeur, pour un gain nul en
sécurité par rapport à des Cloud Functions callable versionnées (`v1_submitTheoryTest`), qui
remplissent le même contrat : appel authentifié, permission vérifiée, version explicite.
**Décision à prendre.**

**Le §50 (hors ligne) et le §19 (paiement instantané) tirent contre le §70.** Un mobile hors ligne
qui accumule des événements de livraison ne doit pas pouvoir fabriquer une transaction financière.
La réponse est l'horodatage serveur et la revalidation à la synchronisation, déjà nommée au §50 —
mais elle suppose que le mobile ne puisse pas écrire dans le ledger, donc, là encore, le palier 2.

**Le §69 demande un staging** que la décision de départ écarte. Tenable pour le portail livreur,
intenable pour les chantiers « courses » et « argent ». À rouvrir avant ceux-là.

---

## 6. Séquence proposée

| Ordre | Chantier | Pourquoi là |
|---|---|---|
| **0** | **Règles Firestore, palier 2** (spec existante) | Prérequis dur. Sans lui, aucune règle métier n'est opposable. |
| **1** | **Portail livreur — socle + parcours d'activation** | Collections neuves, règles restrictives dès l'origine. Ne touche ni les courses ni l'argent. Rend les 30 premiers livreurs gérables de bout en bout. |
| **2** | **KPI, score, niveaux, badges** | Se nourrit des courses. Exige d'abord des courses correctement horodatées. |
| **3** | **Ledger, tarification, partage 80/20, paiements** | Le plus risqué. Exige un staging. |
| **4** | **Courses, disponibilité, attribution, incidents** | Touche `deliveryDispatch` en production. Exige un staging. |

Les chantiers 0 et 1 peuvent avancer en parallèle : le premier sécurise l'existant, le second
construit sur du neuf.

---

## 7. Ce qui reste à décider

1. **API REST versionnée, ou Cloud Functions callable versionnées ?** (§5, première tension)
2. **Le palier 2 des règles est-il lancé avant, ou en parallèle du portail ?**
3. **Staging : on maintient le refus, ou on le crée avant le chantier 3 ?**
4. Les seuils des §24 et §25 (100 courses / score 80 / note 4 ; 500 courses / score 90 / note 4,7)
   sont-ils des valeurs de départ à inscrire en configuration, ou des exemples à revoir ?
