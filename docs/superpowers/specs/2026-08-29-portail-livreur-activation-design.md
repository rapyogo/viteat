# Portail Livreur Viteat — socle et parcours d'activation

**Date :** 2026-08-29
**Statut :** conception, en attente de relecture
**Chantier :** 1 sur 5 du Viteat Driver OS (voir `2026-08-29-viteat-driver-os-audit.md`)
**Périmètre :** nouveau `Drive panel/`, Cloud Functions, `Admin Panel`, collections Firestore neuves
**Ne touche pas :** l'app `driver`, l'app `customer`, `deliveryDispatch`, `restaurant_orders`, la tarification

---

## 1. Objet

Construire l'espace web du livreur et le parcours qui le mène de la candidature à l'activation :
dépôt du dossier, documents, formation, test théorique, simulation pratique, certification,
signature de l'accord, activation.

Couvre les §3 à §11, §36 (partiel), §37 (partiel), §38 (partiel), §39 et §51 (écrans 1, 23 à 26, 29)
du brief Partenaires Livreurs.

**Ce chantier ne produit ni revenu, ni KPI, ni score, ni niveau automatique.** Ces objets viennent
aux chantiers 2 et 3. Le champ `level` existe dès maintenant mais aucune promotion n'est calculée.

---

## 2. Décisions actées

| Sujet | Décision | Où |
|---|---|---|
| Nature de `Drive panel/` | Espace web du livreur, mobile-first | question initiale |
| Administration | Reste dans l'`Admin Panel` | question initiale |
| Règles métier | Cloud Functions, seule autorité | question initiale |
| Forme des API | **Cloud Functions callable versionnées** (`v1_*`), pas de REST | §66, arbitré |
| Sécurité | Palier 2 des règles **en parallèle** ; règles strictes dès la création des collections neuves | arbitré |
| Staging | Pas maintenant ; **obligatoire avant le chantier 3** | §69, arbitré |
| Seuils de niveau | Valeurs du brief inscrites en configuration, modifiables sans redéploiement | §24-25, arbitré |
| Face à la production | Collections neuves, existant intact | question initiale |

---

## 3. Architecture

### 3.1 Trois couches, une autorité par donnée

**`Drive panel/` — Laravel 10 / PHP 8.2.** Sert les pages et vérifie qui est connecté. Rien d'autre.

Le navigateur s'authentifie auprès de Firebase Auth, obtient un ID token, le poste à `POST /session` ;
un middleware le vérifie avec `kreait/firebase-php` et ouvre une session PHP portant l'`uid`. Toute
route protégée l'exige.

**Laravel ne lit jamais Firestore.** Ce n'est pas un choix : PHP 8.2.12 de XAMPP n'a ni `grpc` ni
`protobuf`, et le SDK Firestore serveur les exige. `kreait` v7 vérifie les tokens en pur JWT/HTTP,
sans extension native — c'est ce qui rend le middleware possible.

**Le navigateur — SDK Firebase JS compat 9.23**, même version que les panels existants. Lecture
Firestore en temps réel (checklist qui se coche en direct), upload des pièces vers Firebase Storage.
Il n'écrit jamais un champ que le livreur ne doit pas contrôler.

**Cloud Functions — la seule autorité métier.** Nouveau module
`Order Tracking Firebase Function/functions/products/driver_program.js`.

### 3.2 Mobile-first

Un livreur consulte ce portail sur son téléphone, souvent en 3G, souvent dehors. Blade + Alpine.js,
pas de build lourd. Les règles `# mobile-first` du `CLAUDE.md` s'appliquent intégralement : barre de
navigation basse rétractable au scroll, contenu centré `max-width: 1200px`, troncature par
ellipsis, cibles tactiles ≥ 44 px, aucune couleur en dur — uniquement des `var(--color-*)`.

### 3.3 Identité : une seule par personne

Le §51 et la décision « les deux au choix » demandent connexion par téléphone **et** par email. Pris
au pied de la lettre, cela fabrique des comptes en double : un livreur inscrit par SMS dans l'app
mobile et par email sur le web obtient **deux `uid` distincts**, donc deux dossiers.

**Le téléphone est donc l'identité pivot.** L'inscription se fait toujours par téléphone et OTP —
c'est déjà l'identifiant de l'app mobile. Une fois connecté, le livreur peut ajouter un email et un
mot de passe depuis son profil ; Firebase les rattache au même compte via `linkWithCredential`. Il
se connecte ensuite par l'un ou l'autre, sur un compte unique.

---

## 4. Modèle de données

Toutes les collections sont **neuves**. Aucune collection existante n'est modifiée, à deux
exceptions explicitées au §4.3.

```
driver_program/{uid}
  driverCode      "VT-LVR-000042"          alloué une fois, jamais modifiable
  status          voir §5
  level           1                        1=COMMUNAUTAIRE 2=CERTIFIE 3=AMBASSADEUR
  profile         { firstName, lastName, photoURL, phone, email, address,
                    primaryZoneId, secondaryZoneIds[], vehicleType }
  activation      { identity, documents, training, theoryTest, practicalTest,
                    certification, agreement, payoutAccount, profileComplete }
  dates           { appliedAt, documentsValidatedAt, certifiedAt,
                    agreementSignedAt, activatedAt, levelChangedAt }
  qrToken         32 caractères aléatoires
  referralCode    "VT-REF-000042"          alloué en même temps que driverCode
  referredBy      uid du parrain, ou null

driver_program_history/{autoId}            append-only
  driverId, driverCode, from, to, at, actorId, actorType, reason

driver_documents/{autoId}
  driverId, typeId                         typeId référence la collection `documents` existante
  status          PENDING | APPROVED | REJECTED | EXPIRED
  frontURL, backURL, version, submittedAt
  expiresAt, reviewedAt, reviewedBy, rejectionReason

driver_training/{uid}
  modules         [{ moduleId, startedAt, completedAt }]
  theory          { attempts, bestScore, lastAttemptAt, passedAt }
  practical       { score, ratedBy, ratedAt, notes }
  certifiedAt, certificateNumber

driver_training_modules/{moduleId}         contenu pédagogique, édité par l'admin
  title, order, content, durationMinutes, required, published

driver_training_questions/{questionId}     ILLISIBLE PAR TOUS SAUF LES FUNCTIONS
  text, choices[], correctIndex, moduleId, published

driver_theory_attempts/{attemptId}
  driverId, questionIds[], answers[], score, total, passed, startedAt, submittedAt

driver_signatures/{autoId}                 immuable
  driverId, driverCode, documentType, documentVersion, documentHash,
  fullNameTyped, consentText, signedAt, ip, userAgent

driver_agreements/{documentType}           textes signables, versionnés
  version, title, body, publishedAt, hash

driver_program_settings/config             piloté depuis l'Admin Panel
  codeFormat            "VT-LVR-{seq:6}"
  referralCodeFormat    "VT-REF-{seq:6}"
  requiredDocumentTypes []
  theoryPassScore 24, theoryTotal 30, theoryMaxAttempts 3
  practicalPassScore 16, practicalTotal 20
  documentExpiryWarningDays 30
  levelThresholds       valeurs des §24 et §25, inactives à ce stade

driver_program_counters/{counterId}        transactions atomiques de séquence

driver_audit_log/{autoId}                  append-only, §37
  actorId, actorType, action, entity, entityId, oldValue, newValue, at, ip
```

### 4.1 Ce que le livreur ne peut jamais écrire

Règles Firestore, écrites strictes dès la création :

| Collection | Livreur | Admin | Cloud Function |
|---|---|---|---|
| `driver_program/{uid}` | lecture de son seul document | lecture, aucune écriture directe | seule écriture |
| `driver_program_history` | lecture des siennes | lecture | seule écriture |
| `driver_documents` | lecture des siens | lecture | seule écriture |
| `driver_training/{uid}` | lecture du sien | lecture | seule écriture |
| `driver_training_questions` | **aucun accès** | **aucun accès** | seule lecture |
| `driver_theory_attempts` | **aucun accès** | lecture | seule écriture |
| `driver_signatures` | lecture des siennes | lecture | création seule, ni update ni delete |
| `driver_audit_log` | aucun accès | lecture | seule écriture |
| `driver_program_settings` | lecture | lecture | écriture via Function admin |
| `driver_training_modules` | lecture des publiés | lecture | écriture via Function admin |

Le livreur n'écrit **directement** que deux choses : les fichiers qu'il téléverse dans Firebase
Storage sous `driver_documents/{uid}/`, et rien d'autre. Le reste passe par une Function.

Les questions du test sont illisibles y compris par l'administration : il n'y a aucune raison qu'un
navigateur les charge, et c'est la seule protection réelle contre la fuite du corrigé.

### 4.2 Où l'ancien et le nouveau se rejoignent

`driver_documents.typeId` référence la collection **existante** `documents` — le catalogue des types
de pièces, déjà éditable depuis l'`Admin Panel`. Aucun second catalogue n'est créé (§73).

### 4.3 Les deux seules écritures dans l'existant

Elles sont faites **par Cloud Function uniquement**, et sont le point d'intégration avec l'app
mobile, qui n'est pas modifiée.

| Écriture | Quand | Garde-fou |
|---|---|---|
| `users/{uid}.isActive = true` et `.isDocumentVerify = true` | à l'activation | **Ne passe jamais à `false`.** Un livreur déjà actif ne peut pas être désactivé par ce chantier. |
| `documents_verify/{uid}` — miroir minimal du dossier | à chaque revue de document | Sens unique, écrit par la Function. `driver_documents` reste l'original. |

Ce miroir existe pour que l'app livreur actuelle continue de fonctionner sans une ligne de code
modifiée. Il n'est jamais lu comme source de vérité.

**Ces écritures utilisent `update()` ciblé, jamais `set()`** — la norme N1.8 rappelle que
`FireStoreUtils.updateUser` fait un `set()` sans merge et peut effacer `orderRequestData` et
`inProgressOrderID`, c'est-à-dire faire disparaître une course en cours.

---

## 5. Le parcours

```
CANDIDATURE
   ↓ profil complet + toutes les pièces requises déposées
DOSSIER_A_VERIFIER
   ↓ toutes les pièces APPROVED (admin)
DOCUMENTS_VALIDES
   ↓ premier module ouvert
FORMATION
   ↓ tous les modules requis terminés
TEST
   ↓ score théorique ≥ 24/30
SIMULATION_PRATIQUE
   ↓ note ≥ 16/20 saisie par l'admin
CERTIFIE
   ↓ accord signé
ACCORD_SIGNE
   ↓
PENDING_ACTIVATION
   ↓ les neuf conditions réunies
ACTIVE
```

`PENDING_ACTIVATION` est l'état d'attente du §11 : le parcours est parcouru, mais au moins une
condition de la checklist manque encore — typiquement le compte de paiement, qui ne dépend d'aucune
étape précédente. Un dossier peut y revenir depuis `ACTIVE` si une pièce expire.

Plus deux états hors ligne principale : `REJETE` (dossier refusé, motif obligatoire) et `SUSPENDU`
(décision d'administration, motif obligatoire).

Chaque transition écrit une ligne dans `driver_program_history` et une dans `driver_audit_log`.
**Aucune n'écrase la précédente.** Un dossier rejeté puis re-déposé garde les deux traces.

Les transitions ne sont jamais décidées par le portail : `v1_recomputeStatus` recalcule l'état depuis
les faits enregistrés, à chaque événement. C'est une fonction pure sur l'état du dossier — le même
dossier produit toujours le même statut, ce qui la rend testable sans Firestore.

---

## 6. Cloud Functions

Toutes callable, authentifiées, préfixées `v1_`. Toutes journalisent dans `driver_audit_log`.

### Appelées par le livreur

| Fonction | Contrat |
|---|---|
| `v1_applyAsDriver` | Crée `driver_program/{uid}`, alloue `driverCode` et `referralCode` par transaction atomique sur `driver_program_counters`. Refuse si un dossier existe déjà. Accepte un code de parrainage optionnel. |
| `v1_updateProfile` | Écrit les champs de `profile` uniquement. Rejette toute clé hors liste blanche. |
| `v1_submitDocument` | Enregistre un dépôt en `PENDING`. Vérifie que le fichier existe dans Storage sous le préfixe du livreur. Incrémente `version` si re-dépôt. |
| `v1_startTheoryTest` | Tire les questions selon la configuration, crée un `driver_theory_attempts`, renvoie les énoncés **sans `correctIndex`**. Refuse au-delà de `theoryMaxAttempts`. |
| `v1_submitTheoryTest` | Corrige côté serveur contre `driver_training_questions`. Le corrigé ne quitte jamais le backend. |
| `v1_completeTrainingModule` | Marque un module terminé. |
| `v1_signAgreement` | Vérifie que la version signée est la version publiée, enregistre la signature avec IP, appareil, texte de consentement et empreinte du document. Écriture unique, jamais modifiable. |
| `v1_linkEmailCredential` | Rattache email + mot de passe au compte téléphone existant. |

### Appelées par l'Admin Panel

| Fonction | Contrat |
|---|---|
| `v1_reviewDocument` | `APPROVED` ou `REJECTED` + motif obligatoire si rejet. Met à jour le miroir `documents_verify`. |
| `v1_recordPracticalTest` | Note sur 20, évaluateur, notes libres. |
| `v1_rejectApplication` / `v1_suspendDriver` / `v1_reinstateDriver` | Motif obligatoire. |
| `v1_updateProgramSettings` | Modifie `driver_program_settings`. Audité. |

### Internes

| Fonction | Déclencheur |
|---|---|
| `v1_recomputeStatus` | Appelée par toutes les précédentes. Recalcule `activation`, `status`, écrit l'historique, et à l'activation, met à jour `users`. |
| `expireDriverDocuments` | Planifiée, quotidienne. Passe en `EXPIRED` les pièces échues et notifie `documentExpiryWarningDays` jours avant l'échéance. |

### Vérification publique du QR

`v1_verifyDriverQr` — **HTTP, non authentifiée**, limitée en débit par IP. Reçoit un `qrToken`,
renvoie uniquement : prénom, initiale du nom, photo, `driverCode`, niveau, `certifie: true|false`,
`actif: true|false`.

Ni téléphone, ni email, ni adresse, ni zone, ni identifiant technique. Un QR code se photographie et
se partage ; il finit sur des écrans qu'on ne choisit pas. Le token est aléatoire et non déductible
de l'`uid`, ce qui permet de le régénérer si un badge est perdu.

C'est aussi la raison pour laquelle cette page passe par une Function HTTP et non par Firestore :
Laravel ne peut pas lire Firestore, et ouvrir `driver_program` en lecture publique pour servir un
badge exposerait toute la collection.

---

## 7. Checklist d'activation

Les neuf conditions du §11, recalculées par `v1_recomputeStatus` :

| Condition | Vérifiée par |
|---|---|
| `identity` | pièce d'identité `APPROVED` |
| `documents` | toutes les pièces de `requiredDocumentTypes` en `APPROVED` et non expirées |
| `training` | tous les modules `required` et `published` terminés |
| `theoryTest` | `bestScore ≥ theoryPassScore` |
| `practicalTest` | `practical.score ≥ practicalPassScore` |
| `certification` | `certifiedAt` renseigné |
| `agreement` | signature de la version courante de chaque document obligatoire |
| `payoutAccount` | `users.userBankDetails` ou une méthode de retrait renseignée |
| `profileComplete` | tous les champs obligatoires de `profile` remplis |

Toutes vraies → `ACTIVE`. Une seule fausse → `PENDING_ACTIVATION`. Le livreur voit en temps réel
laquelle manque, avec l'action qui la débloque.

La signature est liée à une **version** de document. Si l'accord est republié, la condition
`agreement` redevient fausse pour tout le monde et chacun doit re-signer — c'est le comportement
voulu, mais il faut en avoir conscience avant de republier un texte : cela désactive le réseau.
Une republication doit donc être une décision explicite, jamais une correction de coquille.

---

## 8. Écrans

### Portail livreur

| # | Écran | Route |
|---|---|---|
| 1 | Connexion — téléphone/OTP, ou email/mot de passe si rattaché | `/` |
| 2 | Candidature — profil, zone, moyen de déplacement, code de parrainage | `/candidature` |
| 3 | Mon dossier — checklist en temps réel, prochaine action mise en avant | `/dossier` |
| 4 | Mes documents — dépôt, statut, motif de rejet, échéances | `/documents` |
| 5 | Formation — modules, progression | `/formation` |
| 6 | Test théorique — 30 questions, tentatives restantes | `/formation/test` |
| 7 | Ma certification — attestation numérique téléchargeable | `/certification` |
| 8 | Signature de l'accord — texte, consentement explicite, copie téléchargeable | `/accord` |
| 9 | Mon profil — ID, QR code, rattachement email | `/profil` |
| 10 | Vérification publique — **hors authentification** | `/v/{qrToken}` |

### Admin Panel — vues neuves

`DriverProgramController`, sans toucher au `DriverController` existant :

- File des dossiers à vérifier, filtrable par statut et par zone
- Revue pièce par pièce, motif de rejet obligatoire
- Saisie de la note de simulation pratique
- Éditeur des modules et de la banque de questions
- Réglages du programme (§64, périmètre livreur)
- Fiche livreur : timeline (§36) et journal d'audit (§37)

### RBAC (§39)

La table `role` ne contient qu'un rôle. Ce chantier en ajoute trois, les seuls dont il a besoin :

| Rôle | Droits sur ce périmètre |
|---|---|
| `SUPER_ADMIN` | tout (existant) |
| `OPERATIONS_MANAGER` | dossiers, documents, suspension, réglages |
| `TRAINING_MANAGER` | modules, questions, note de simulation — **pas** la suspension |

`FINANCE_MANAGER`, `SUPPORT_AGENT` et `ADMIN_VIEWER` viendront avec les chantiers qui les concernent.
Créer six rôles vides maintenant donnerait l'illusion d'un cloisonnement qui n'existe pas encore.

---

## 9. Les comptes livreurs existants

Relevé sur `rapyogo-2bccd` le 2026-08-29 :

| Mesure | Nombre |
|---|---|
| Documents `users` avec `role == "driver"` | **383** |
| dont `isActive == true` | **8** |
| dont `isDocumentVerify == true` | 12 |
| dont `fcmToken` présent | 370 |
| dont `zoneId` renseigné | **42** |
| dont coordonnées bancaires | 138 |

L'objectif de 30 livreurs est un objectif **d'activation à court terme**, pas un effectif existant.
Le terrain est l'inverse de ce que je supposais : il n'y a pas trente partenaires à reprendre, il y a
**383 comptes ouverts dont 8 fonctionnent**. Le portail n'a donc pas à migrer une flotte — il a à
faire remonter une file d'attente.

Un chiffre mérite d'être isolé : `deliveryDispatch` exige `driver.zoneId == zone de la commande`.
**341 comptes sur 383 n'ont aucune zone** et ne peuvent, structurellement, recevoir aucune course.
Ce n'est pas un problème créé par ce chantier, mais il explique l'écart entre 383 inscrits et
8 actifs, et le portail doit rendre la zone obligatoire à la candidature.

### Reprise

Deux populations, deux traitements. Aucune ne perd son accès.

**Les 8 actifs** — `status: ACTIVE`, `level: 1`, `dates.activatedAt` = leur `createdAt`, checklist
marquée acquise par antériorité. Ils ne repassent ni par la formation ni par la certification.
Seul `agreement` reste **faux** : une signature ne se présume pas. Ils continuent de livrer
normalement, et le portail leur demande de signer à leur première connexion.

**Les 375 autres** — `status: CANDIDATURE`, checklist vide, `driverCode` alloué. Ils entrent dans
l'entonnoir normal : compléter le profil, choisir une zone, déposer les pièces. C'est précisément
ce que le portail est fait pour absorber, et c'est de cette file que sortiront les 30 activations
visées.

Le script est exécuté d'abord sur un seul compte de chaque population, vérifié, puis sur le reste.

**Il alloue 383 `driverCode` séquentiellement, jamais en parallèle.** Ce n'est pas une précaution
de style : les 383 allocations tirent sur un **document compteur unique**, et Firestore plafonne
les écritures soutenues sur un document isolé autour d'une par seconde. Mesuré sur l'émulateur le
2026-08-30 : vingt transactions concurrentes sur ce même document prennent 7,7 à 12,4 secondes et
ont produit deux `Transaction lock timeout`, dont un sur un émulateur démarré à froid. La
transaction elle-même est correcte — c'est l'appelant qui ne doit pas la marteler.

Le script de reprise traite donc les comptes **un par un**, avec une pause entre chacun, et
journalise sa progression pour pouvoir reprendre après interruption sans réallouer. Une reprise
de 383 comptes prend ainsi quelques minutes : c'est le prix d'identifiants sans doublon.

### Le catalogue de documents est celui du template indien

Les cinq types configurés dans `documents` sont `RC Book`, `FSSAI Certificate`, `Driving License`,
`ID Proof` et `Autorisation d'ouverture`. Les deux premiers sont des documents réglementaires
indiens sans objet en RDC. Aucun des cinq n'a `expireAt` renseigné — la gestion d'expiration du §7
n'est configurée nulle part.

Ce catalogue est à redéfinir pour Goma **avant** l'ouverture du portail, sinon les candidats
déposeront des pièces qui ne veulent rien dire. C'est une décision métier, pas technique : elle
appartient à l'exploitation, et le plan d'implémentation la porte comme une tâche à part entière.

Même remarque sur `zone` : sept zones, dont `Worldwide` et `World Wide` en doublon. À nettoyer avant
de rendre la zone obligatoire.

---

## 10. Ce que nous ne faisons pas

- **Modifier l'app livreur Flutter.** Le miroir dans `users` et `documents_verify` la laisse
  fonctionner à l'identique. Elle sera reprise à un chantier ultérieur.
- **Toucher `deliveryDispatch`** ou les statuts de `restaurant_orders`. Quatre applications lisent
  ces chaînes.
- **Calculer un score, un KPI ou un niveau.** Le champ `level` existe, aucune promotion n'est
  calculée. Les seuils sont en configuration, inactifs.
- **Créer une table MySQL métier.** Voir l'audit, §3.1.
- **Créer une API REST.** Décision actée : callable versionnées.
- **Désactiver un livreur actif.** Le miroir ne pose `isActive` qu'à `true`.

---

## 11. Tests

**Fonctions pures, en tests unitaires** — c'est là qu'est le risque réel :

1. Allocation de `driverCode` : unicité sous appels concurrents, respect du format configuré
2. Correction du test théorique : score juste, seuil, tentatives épuisées
3. Calcul de la checklist : les neuf conditions, chacune isolément, puis toutes ensemble
4. Calcul du statut : chaque transition légale, et le refus de chaque transition illégale
5. Expiration des documents : bascule `EXPIRED`, fenêtre d'alerte

**Règles Firestore, sur émulateur** — pour chaque collection neuve, un cas autorisé et un cas
refusé par rôle. En particulier : un livreur qui tente d'écrire son propre `level`, son `status`,
son `driverCode` ; un livreur qui tente de lire `driver_training_questions` ; un livreur qui tente
de lire le dossier d'un autre.

**Laravel** : middleware d'authentification contre un token contrefait, un token expiré, un token
valide, et une absence de token.

**Manuel, avant toute ouverture** : un parcours candidat complet de bout en bout, sur téléphone, en
3G bridée.

---

## 12. Déploiement et retour arrière

**Ordre** : collections et règles neuves → Cloud Functions → portail → vues de l'Admin Panel →
reprise des 30 livreurs.

Les Functions sont déployées **en cible** (`--only functions:v1_...`), jamais globalement :
`helloWorld` et `sendNewOrderNotification`, d'origine inconnue, ne doivent pas être touchées.

**Sauvegarde préalable obligatoire** de `Admin Panel/` et de
`Order Tracking Firebase Function/functions/` — ni l'un ni l'autre n'est sous git, toute
modification y est immédiatement définitive.

**Retour arrière** : les collections étant neuves, les supprimer ne casse rien. Le seul point non
réversible par simple suppression est le miroir dans `users` — d'où la règle « jamais à `false` ».
Le PITR de 7 jours, activé le 2026-08-29, couvre le reste.

---

## 13. Risques

| Risque | Portée | Traitement |
|---|---|---|
| **Les règles de production sont ouvertes** | Les collections neuves sont protégées dès la publication de leurs propres règles — le `if true` des autres ne les affecte pas. En revanche `users`, `wallet` et `documents_verify` restent écrivables par n'importe qui jusqu'au palier 2. | Règles strictes écrites en même temps que chaque collection neuve. Ne jamais traiter `users` comme une source fiable avant le palier 2. |
| **Un document expiré ne suspend pas les livraisons** | Une pièce échue fait repasser le dossier en `PENDING_ACTIVATION`, mais `users.isActive` reste à `true` : le livreur continue de recevoir des courses. C'est la conséquence directe de la règle « jamais à `false` ». | Assumé pour ce chantier — désactiver un livreur en cours de service est une décision d'exploitation, pas un effet de bord d'un script. L'expiration remonte une alerte dans l'`Admin Panel` ; la suspension reste manuelle, via `v1_suspendDriver`. À reprendre au chantier 4. |
| Écriture dans `users` à l'activation | Un `set()` sans merge effacerait une course en cours (norme N1.8) | `update()` ciblé, sur deux champs nommés, jamais `set()` |
| Republication d'un accord | Désactive tout le réseau jusqu'à re-signature | Avertissement explicite dans l'écran d'édition ; décision d'administration |
| Reprise des 30 livreurs | Un script fautif casse des comptes actifs | Exécution sur un livreur d'abord, vérification, puis le reste |
| `composer` absent de la machine | Le projet Laravel ne peut pas être créé | À installer avant le démarrage |
| Pas de staging | Une erreur se voit en production | Ce chantier n'écrit que dans du neuf, sauf les deux champs miroir |

---

## 14. Suite

Une fois ce chantier livré et le palier 2 des règles déployé : chantier 2 — KPI, score Viteat,
niveaux et badges, qui s'appuie sur les données de courses et requiert d'abord leur horodatage
côté serveur.
