# Callables de lecture pour l'administration — programme Partenaires Livreurs

**Date :** 2026-08-31
**Statut :** conception validée par l'utilisateur, en attente de relecture
**Chantier :** préalable du plan 1C (vues d'administration du Viteat Driver OS)
**Dépend de :** chantier 1A (module `driver_program/`, 13 callables déployées), claim `admin` de
l'Admin Panel (construit et vérifié le 2026-08-31)
**Ne touche pas :** le portail livreur (`Drive panel/`), les apps Flutter, `deliveryDispatch`,
le déploiement des règles Firestore (chantier sécurisation), la reprise des 383 comptes

---

## 1. Objet

Le chantier 1A n'a produit que des fonctions d'**écriture**. Les vues d'administration du plan 1C
(file des dossiers, fiche livreur, revue pièce par pièce, timeline, journal d'audit, réglages,
éditeur de modules et de questions) n'ont **rien à lire**. Ce chantier produit les fonctions
callable de lecture qui les alimentent.

Lecture **seule** : les écritures manquantes (édition des modules et des questions, validation du
schéma de `v1_updateProgramSettings`) sont un chantier séparé, qui accompagnera la construction
des vues d'édition. Deux retouches d'écriture minimes et assumées sont incluses — voir §6.

---

## 2. Décisions actées

| Sujet | Décision | Source |
|---|---|---|
| Périmètre | Lecture seule | question utilisateur du 2026-08-31 |
| Forme | Sept fonctions callable dédiées (`v1_*`), pas de fonction générique | approche A, validée |
| Lecture directe navigateur | Écartée : `driver_training_questions` est fermée à tous par les règles, et deux mécanismes de lecture en parallèle seraient incohérents | §3 |
| Tri par défaut de la file | Ancienneté croissante (`dates.appliedAt`), tie-break `__name__` | question utilisateur |
| Recherche dans la file | Nom (préfixe, champ normalisé) + code `VT-*` + téléphone, routée par la forme du terme | question utilisateur |
| Filtre par zone | Sur `profile.primaryZoneId` — source de vérité unique de la zone du programme | §4.1 |
| Fiche | Valeurs **mémorisées** de `status` et `activation` ; aucun recalcul | §4.2 |
| RBAC | `requireAdmin` partout ; le RBAC fin (OPERATIONS/TRAINING) reste côté Laravel, sur les vues | §7 |

---

## 3. Architecture

Nouveau module `read_callables.js` dans `Order Tracking Firebase Function/functions/products/driver_program/`,
à côté de `callables.js` et `admin_callables.js`. Mêmes conventions que l'existant :

- fonctions `v1_*` callable, authentifiées, exigeant `requireAdmin` (claim `role === 'admin'`) ;
- tout refus lève `HttpsError('failed-precondition', message français)` — le code ne discrimine
  pas les cas, le message est la seule information ;
- la logique testable est extraite en **fonctions pures** dans `read_models.js` (aucune
  importation Firebase), sur le modèle de `rules.js` ;
- contraintes ESLint 2017 non négociables : ni `?.`, ni `??`, ni spread d'objet.

Les fonctions lisent Firestore via le SDK admin : elles **ignorent les règles**, ce qui rend les
vues d'administration indépendantes du calendrier de déploiement de `firestore.rules`, et rend
possible la lecture de `driver_training_questions`, que les règles ferment à tout le monde.

---

## 4. Les sept fonctions

### 4.1 `v1_listDriverDossiers` — la file

**Entrée** `data` :

| Champ | Contrainte |
|---|---|
| `status` | facultatif ; doit appartenir aux 12 statuts (`rules.STATUSES`), sinon refus |
| `zoneId` | facultatif ; chaîne non vide |
| `search` | facultatif ; chaîne non vide, 80 caractères max |
| `pageSize` | facultatif ; entier 1..100, défaut 50 |
| `cursor` | facultatif ; objet opaque rendu par la réponse précédente, repassé tel quel |

**Requête** : `driver_program`, tri `dates.appliedAt` croissant puis `__name__` croissant
(tie-break déterministe). Filtres cumulables, chacun avec son index composite (§5) :

- `status` → `where('status', '==', status)`
- `zoneId` → `where('profile.primaryZoneId', '==', zoneId)`
- `search` → routé par la forme du terme (fonction pure `routeSearch`) :
  - préfixe `VT-` (insensible à la casse) → préfixe sur `driverCode`, terme normalisé en
    majuscules (`normalizeCodeTerm`) ;
  - uniquement des chiffres, des espaces et des `+` → préfixe sur `profile.phone` ;
  - sinon → préfixe sur `searchName` via `normalizeSearchName` (§6.1).
  - Un préfixe Firestore s'écrit `where(f, '>=', terme).where(f, '<', terme + '')`.
- `cursor` → `startAfter(timestamp reconstruit, lastId)`.

**Jointure** : la collection `zone` est lue en entier (7 documents) en parallèle de la requête,
pour mapper `primaryZoneId` → nom.

**Réponse** :

```
{
  items: [ {
    uid, driverCode, firstName, lastName, phone, status,
    primaryZoneId, zoneName,          // zoneName null si la zone n'existe pas
    appliedAt,                        // ISO 8601
    activatedAt                       // ISO 8601 ou null
  } ],
  nextCursor: { appliedAt: {seconds, nanoseconds}, lastId } | null
}
```

`nextCursor` est nul quand la page rendue compte moins de `pageSize` éléments ; sinon c'est le
curseur du dernier élément, à repasser tel quel dans `cursor` au prochain appel. Le curseur porte
le `Timestamp` Firestore **entier** (secondes + nanosecondes) : aucune conversion en millis,
donc aucune perte de précision ni risque de doublon en frontière de page.

**Ne sort pas de cette fonction** : adresse, email, `qrToken`, numéro de compte, tout le détail
du dossier — la file est une vue d'aiguillage, la fiche (§4.2) porte le détail.

### 4.2 `v1_getDriverDossier` — la fiche

**Entrée** : `{ uid }`, chaîne non vide.

**Sortie** :

```
{
  program:    { driverCode, referralCode, level, status, adminStatus, dates },
  profile:    { firstName, lastName, photoURL, phone, email, address,
                primaryZoneId, secondaryZoneIds, vehicleType },
  user:       { zoneId, payoutReady, hasFcmToken },      // présences, jamais les valeurs
  documents:  [ { id, typeId, title, status, rejectionReason, frontURL, backURL,
                  version, submittedAt, expiresAt, reviewedAt, reviewedBy } ],
  training:   { modules, theory, practical, certifiedAt, certificateNumber },
  signatures: [ { documentType, documentVersion, fullNameTyped, signedAt, ip, userAgent } ],
  activation: { les neuf booléens mémorisés },
  requiredDocumentTypes: [ ... ],        // settings.requiredDocumentTypes
  requiredModuleIds:     [ ... ],        // modules requis publiés
  agreementVersions:     { ... }         // version en vigueur par type d'accord
}
```

- `title` est résolu par jointure sur la collection existante `documents` (le catalogue) ;
  `typeId` inconnu → `title: null`.
- Les pièces sont triées par `submittedAt` décroissant (le dépôt le plus récent d'abord).
- `payoutReady` vaut `true` quand `users.userBankDetails` est présent et non vide — le détail du
  compte ne sort jamais.
- `hasFcmToken` : présence de `users.fcmToken`, jamais la valeur.
- `status` et `activation` sont lus tels que mémorisés dans `driver_program`. **Aucun recalcul** :
  la fiche est un outil de vérification, pas un moteur. La checklist mémorisée est recalculée à
  chaque événement du parcours ; afficher autre chose introduirait deux vérités concurrentes.
- Implémentation : réutilise `store.loadDossier` (7 lectures en parallèle) + 1 lecture du
  catalogue `documents`.

### 4.3 `v1_listDriverHistory` — timeline d'un dossier

**Entrée** : `{ uid, pageSize?, cursor? }`.

**Sortie** : lignes de `driver_program_history` du dossier, tri `at` **décroissant** (les plus
récentes d'abord), même mécanisme de curseur qu'en §4.1 (curseur `{ at, lastId }`).

```
items: [ { id, from, to, at, actorId, actorType, reason, driverCode } ]
```

### 4.4 `v1_listDriverAudit` — journal d'audit

**Entrée** : `{ driverId?, pageSize?, cursor? }`. Sans `driverId`, renvoie le journal **global**
(toutes les lignes) ; avec, le journal du dossier. Tri `at` décroissant, paginé.

```
items: [ { id, actorId, actorType, action, entity, entityId,
           oldValue, newValue, at, ip, driverId } ]
```

Le filtre par dossier repose sur le champ `driverId` ajouté à `driver_audit_log` (§6.2). Les
lignes écrites avant cette retouche (journal de test du chantier 1A) ne portent pas ce champ :
invisibles du filtre par dossier, toujours visibles du journal global. Assumé — le programme
n'est pas encore ouvert.

### 4.5 `v1_getProgramSettings`

Aucun argument. Rend le document `driver_program_settings/config` tel quel. Les clés possibles :
`codeFormat`, `referralCodeFormat`, `requiredDocumentTypes`, `identityDocumentType`,
`requiredAgreements`, `theoryPassScore`, `theoryTotal`, `theoryMaxAttempts`,
`practicalPassScore`, `practicalTotal`, `documentExpiryWarningDays`, `levelThresholds`.

### 4.6 `v1_listTrainingModules`

Aucun argument. Rend **tous** les modules de `driver_training_modules` — publiés et brouillons,
l'éditeur a besoin des deux — triés par `__name__`. Tri volontairement **sans** `order` : une
requête ordonnée sur ce champ exclurait silencieusement tout module qui ne le porte pas — l'ordre
d'affichage est l'affaire des vues.

```
items: [ { id, title, order, content, durationMinutes, required, published } ]
```

### 4.7 `v1_listTrainingQuestions`

Aucun argument. Rend **toutes** les questions de `driver_training_questions` **avec leur
`correctIndex`**, triées par `__name__`. Tri volontairement **sans** `moduleId` : une requête
ordonnée sur ce champ exclurait silencieusement toute question qui ne le porte pas — le
regroupement par module se fera côté vues. C'est le seul chemin par lequel le corrigé sort du
backend : réservé à un appelant porteur du claim admin, et assumé — sans lui, aucun éditeur de
banque de questions n'est possible.

```
items: [ { id, text, choices, correctIndex, moduleId, published } ]
```

---

## 5. Index composites

Une clause d'égalité ou de préfixe combinée à un `orderBy` sur un autre champ exige un index
composite. À ajouter à `Firebase Indexing/firestore_indexes.json` puis déployer
(`firebase deploy --only firestore:indexes`).

| Collection | Champs |
|---|---|
| `driver_program` | `status` ASC, `dates.appliedAt` ASC, `__name__` ASC |
| `driver_program` | `profile.primaryZoneId` ASC, `dates.appliedAt` ASC, `__name__` ASC |
| `driver_program` | `searchName` ASC, `dates.appliedAt` ASC, `__name__` ASC |
| `driver_program` | `driverCode` ASC, `dates.appliedAt` ASC, `__name__` ASC |
| `driver_program` | `profile.phone` ASC, `dates.appliedAt` ASC, `__name__` ASC |
| `driver_program_history` | `driverId` ASC, `at` DESC, `__name__` DESC |
| `driver_audit_log` | `driverId` ASC, `at` DESC, `__name__` DESC |

La file **sans filtre** (uniquement `orderBy dates.appliedAt`) et le journal d'audit **global**
(uniquement `orderBy at`) n'ont besoin d'aucun index composite : Firestore indexe automatiquement
chaque champ, ascendant et descendant, et refuse (`HTTP 400 : this index is not necessary`) tout
composite à un seul champ plus `__name__` — vérifié au déploiement du 2026-08-31.

Les index se déploient **avant** les fonctions : leur construction prend du temps, et une
fonction déployée qui requête sans index échoue.

---

## 6. Les deux retouches d'écriture assumées

### 6.1 `searchName` — la recherche par nom

Firestore ne fait pas de recherche partielle. La recherche par nom passe donc par un champ
normalisé maintenu à l'écriture. `normalizeSearchName(firstName, lastName)` (fonction pure) :

- concatène `"firstName lastName"` (lastName vide → firstName seul) ;
- minuscules ;
- suppression des accents (décomposition NFD puis retrait des marques) ;
- espaces multiples écrasés en un seul, bordures coupées.

Posé à `applyAsDriver` (dans le `set` initial, même vide) et à chaque `updateProfile` qui touche
`firstName` ou `lastName` (recalculé et ajouté au patch). `normalizeSearchName` vit dans
`read_models.js` ; `callables.js` l'importe.

**Prérequis posé au plan de reprise (1C)** : le script qui reprend les 383 comptes doit poser
`dates.appliedAt` **et** `searchName` sur chaque dossier créé. Sans `appliedAt`, un dossier est
invisible de la file (une requête ordonnée sur ce champ exclut les documents qui ne le portent
pas) ; sans `searchName`, il est introuvable par la recherche. Les quelques dossiers créés en
test par le chantier 1A sont à compléter de la même façon.

### 6.2 `driverId` dans `driver_audit_log`

`store.appendAudit` accepte un champ `driverId` optionnel (défaut `null`) et l'écrit. Les cinq
sites d'écriture portant sur un dossier le fournissent : `reviewDocument` (le `driverId` y est
déjà lu), `recordPracticalTest`, `setAdminStatus` (suspendre/réintégrer/rejeter),
`updateProgramSettings` reste global (`driverId: null`). Sans ce champ, filtrer le journal par
dossier exigerait une jointure artificielle par `entity`/`entityId` illisible.

---

## 7. Sécurité

- **`requireAdmin` sur les sept fonctions.** Une simple connexion ne suffit jamais.
- **RBAC fin côté Laravel, pas dans les claims.** OPERATIONS_MANAGER et TRAINING_MANAGER sont
  des rôles de vues : ils déterminent quels écrans existent et donc quelles fonctions sont
  appelables depuis l'interface. Les callables n'exigent que `role === 'admin'`, comme les six
  fonctions d'écriture existantes. Limite assumée et documentée : un admin connecté peut appeler
  n'importe quelle fonction depuis la console du navigateur — acceptable tant que Laravel ne
  porte qu'un seul rôle réel. Si un jour le cloisonnement doit être étanche côté API, on posera
  des claims par rôle ; ce n'est pas le périmètre de ce chantier.
- **Le corrigé ne sort que par `v1_listTrainingQuestions`**, à un appelant authentifié porteur du
  claim admin. Les vues qui l'affichent ne doivent pas le mettre en cache.
- **Présences, jamais valeurs** : la fiche rend `payoutReady` et `hasFcmToken`, pas le détail
  bancaire ni le jeton FCM. La file rend moins encore (§4.1).
- **Rien d'inutile ne sort** : ni `qrToken`, ni `referredBy`, ni adresse dans la file.
- Les collections sensibles restent régies par `firestore.rules` (écrit, testé, non déployé) ;
  ces fonctions ne dépendent pas de son calendrier.

---

## 8. Fonctions pures — `read_models.js`

Nouveau fichier pur, aucune importation Firebase, sur le modèle de `rules.js` :

| Fonction | Contrat |
|---|---|
| `normalizeSearchName(firstName, lastName)` | §6.1 |
| `normalizeCodeTerm(term)` | majuscules, bordures coupées |
| `routeSearch(term)` | `'code'` si préfixe `VT-`, `'phone'` si uniquement chiffres/`+`/espaces, `'name'` sinon |
| `validateListInput(data)` | rend un objet normalisé `{ status, zoneId, search, pageSize, cursor }` ou lève une `Error` française : statut hors liste, `pageSize` non entier ou hors 1..100, `search` vide ou > 80 caractères, `cursor` de forme inattendue |
| `validateUid(uid)` | chaîne non vide, sinon `Error` française |
| `encodeCursor(timestampLike, id)` | `{ [champ]: {seconds, nanoseconds}, lastId }` |
| `decodeCursor(cursor, champ)` | reconstruit `{ timestamp: {seconds, nanoseconds}, lastId }` ou lève si malformé |
| `buildDossierRow(doc, zonesById)` | projection de ligne de file (§4.1) |
| `buildDossierDetail(dossier, catalogById)` | projection de fiche (§4.2), `payoutReady` et `title` inclus |

---

## 9. Tests

`node --test` **sans argument** (forme correcte du module), dans
`functions/test/` à côté des tests du chantier 1A. Les lectures elles-mêmes ne contiennent pas de
métier : tout le risque est dans les pures, et c'est là qu'on teste.

- `normalizeSearchName` : accents (`É` → `e`), majuscules, espaces multiples, lastName vide,
  entrées vides ;
- `routeSearch` : `VT-LVR-000042` → code, `vt-...` → code, `0998123456` → phone,
  `+243998123456` → phone, `rosty` → name ;
- `buildDossierRow` : champs projetés et seulement eux, `zoneName` mappé, zone inconnue → null,
  dates en ISO ;
- `buildDossierDetail` : `payoutReady` vrai/faux selon `userBankDetails` vide ou non, `title`
  résolu, `typeId` inconnu → `title: null` ;
- `validateListInput` : statut invalide refusé, `pageSize` 0 / 101 / non numérique refusé,
  curseur malformé refusé, valeurs par défaut appliquées ;
- `encodeCursor`/`decodeCursor` : aller-retour, curseur tronqué refusé.

---

## 10. Déploiement et vérification

**Ordre :** index composites (§5) d'abord, puis les fonctions **en cible** :

```
firebase deploy --only functions:v1_listDriverDossiers,functions:v1_getDriverDossier,functions:v1_listDriverHistory,functions:v1_listDriverAudit,functions:v1_getProgramSettings,functions:v1_listTrainingModules,functions:v1_listTrainingQuestions --project rapyogo-2bccd
```

Jamais de déploiement global : `helloWorld` et `sendNewOrderNotification` ne doivent pas être
touchées. Un échec « An unexpected error has occurred » à la découverte des fonctions est
transitoire : relancer suffit.

**Vérification après déploiement :** appel de chaque fonction avec un token portant
`role: 'admin'` (script local `firebase-admin` avec `createCustomToken`, ou le canal Laravel du
panel une fois les vues branchées) : file sans filtre, file filtrée par statut et par zone,
recherche dans les trois formes, pagination complète, fiche d'un dossier de test, timeline,
audit global et filtré, réglages, modules, questions avec corrigé.

---

## 11. Hors périmètre

- `v1_verifyDriverQr` et `expireDriverDocuments` (tâches 14 et 15 reportées du 1A) ;
- les écritures de l'éditeur de contenu (créer/éditer/publier modules et questions) — chantier
  qui accompagnera les vues d'édition ;
- la validation du schéma de `v1_updateProgramSettings` ;
- le déploiement de `firestore.rules` (chantier sécurisation) ;
- la reprise des 383 comptes (plan 1C) — ce chantier en porte seulement les prérequis (§6.1) ;
- les rôles Laravel OPERATIONS_MANAGER / TRAINING_MANAGER.

---

## 12. Risques

| Risque | Traitement |
|---|---|
| Un dossier sans `dates.appliedAt` est **invisible de la file** (une requête ordonnée sur ce champ exclut les documents qui ne le portent pas) | Prérequis explicite posé à la reprise (§6.1) ; vérification post-reprise : compter les dossiers sans `appliedAt` |
| Un dossier sans `searchName` est introuvable par la recherche | Même prérequis |
| Les lignes d'audit antérieures à la retouche §6.2 sont invisibles du filtre par dossier | Assumé (journal de test) ; le journal global les montre |
| Réponse callable plafonnée à 10 Mo | La file à 100 lignes et la fiche sont loin du plafond ; la pagination est obligatoire partout |
| Le corrigé est visible dans le navigateur d'un admin connecté | Assumé et nécessaire à l'éditeur ; pas de mise en cache côté vues |
| `v1_listDriverAudit` global croît avec l'activité | Pagination systématique ; un filtre par action pourra être ajouté plus tard si le volume l'exige |
