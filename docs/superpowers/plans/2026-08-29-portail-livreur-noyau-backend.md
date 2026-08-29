# Portail Livreur — noyau backend (plan 1A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construire l'autorité métier du parcours candidature → activation : fonctions pures testées, Cloud Functions `v1_*` callable, et règles Firestore strictes sur les collections neuves.

**Architecture:** Trois couches dans `products/driver_program/`. `rules.js` ne contient que des fonctions pures — aucun accès Firestore, c'est là que vit toute la logique métier et l'essentiel des tests. `store.js` porte les accès Firestore. `callables.js` et `admin_callables.js` exposent les fonctions appelables et n'y mettent aucune décision. Cette séparation est ce qui rend le métier testable sans émulateur.

**Tech Stack:** Node 20, `firebase-admin@^11.11.1` (API namespacée), `firebase-functions@^7.3.2` importé via `firebase-functions/v1`, `node:test` pour les tests unitaires, émulateur Firestore + `@firebase/rules-unit-testing` pour les règles.

**Spec:** `customer/docs/superpowers/specs/2026-08-29-portail-livreur-activation-design.md`

**Audit:** `customer/docs/superpowers/specs/2026-08-29-viteat-driver-os-audit.md`

## Global Constraints

Ces contraintes s'appliquent à **chaque tâche**. Elles ne sont pas négociables : les cinq premières font échouer le déploiement si elles sont violées, parce que `firebase.json` lance `npm run lint` en `predeploy`.

- **ESLint `ecmaVersion: 2017`.** Interdits : optional chaining `?.`, nullish coalescing `??`, spread d'objet `{...x}`. Utiliser `Object.assign({}, x)`. `async`/`await`, destructuring, template literals et arrow functions sont autorisés.
- **`no-await-in-loop` est une erreur.** Jamais d'`await` dans une boucle. Utiliser `Promise.all` sur un tableau construit par `map`.
- **`eqeqeq` et `no-eq-null` sont des erreurs.** Toujours `===` et `!==`. Jamais `== null` — écrire `=== null || === undefined`, ou tester la valeur voulue.
- **`promise/always-return` et `promise/catch-or-return` sont des erreurs.** Tout `.then()` retourne une valeur, toute chaîne se termine par `.catch()`.
- **`callback-return` et `handle-callback-err` sont des erreurs.**
- **Déploiement toujours ciblé** : `firebase deploy --only functions:nom1,functions:nom2`. Jamais `--only functions` seul. Les fonctions `helloWorld` et `sendNewOrderNotification`, d'origine inconnue, ne doivent jamais être touchées.
- **Projet Firebase : `rapyogo-2bccd`, c'est la production.** Il n'y a pas de staging. Les collections créées par ce plan sont neuves, donc sans risque de régression — mais toute écriture dans `users` ou `documents_verify` touche du vivant.
- **`Order Tracking Firebase Function/` n'est pas un dépôt git.** Une copie de sauvegarde datée est faite en tâche 1 et n'est plus refaite ensuite.
- **Écriture dans `users` : `update()` ciblé, jamais `set()`.** Un `set()` sans merge efface `orderRequestData` et `inProgressOrderID`, c'est-à-dire une course en cours (norme N1.8).
- **`users.isActive` n'est jamais mis à `false` par ce plan.** Uniquement à `true`.
- **Tous les messages destinés à un humain sont en français.**
- Nom du projet Firebase en dur nulle part : lire `admin.app().options.projectId`.

---

## Structure des fichiers

| Fichier | Responsabilité |
|---|---|
| `functions/products/driver_program/rules.js` | **Fonctions pures.** Format de code, correction du test, checklist, statut. Zéro dépendance Firebase. |
| `functions/products/driver_program/store.js` | Accès Firestore : lecture du dossier, allocation atomique de séquence, écriture d'historique et d'audit. |
| `functions/products/driver_program/callables.js` | Fonctions `v1_*` appelées par le livreur. |
| `functions/products/driver_program/admin_callables.js` | Fonctions `v1_*` appelées par l'Admin Panel. |
| `functions/products/driver_program/public.js` | `v1_verifyDriverQr`, HTTP non authentifiée. |
| `functions/products/driver_program/scheduled.js` | Expiration quotidienne des documents. |
| `functions/test/driver_program/rules.test.js` | Tests unitaires des fonctions pures. |
| `functions/test/driver_program/store.test.js` | Tests d'intégration de l'allocation, sur émulateur. |
| `functions/test/rules/driver_program.rules.test.js` | Tests des règles Firestore, sur émulateur. |
| `firestore.rules` | Règles des collections neuves. |
| `firebase.json` | Modifié : ajout du bloc `firestore` et `emulators`. |
| `functions/index.js` | Modifié : câblage des nouvelles fonctions. |

`rules.js` est le fichier qui compte. Tout ce qui décide y vit, et rien d'autre n'y vit. Un lecteur doit pouvoir comprendre le programme Partenaires Livreurs en lisant ce seul fichier.

---

### Task 1: Sauvegarde, outillage de test et squelette

**Files:**
- Create: `Order Tracking Firebase Function/functions/products/driver_program/rules.js`
- Create: `Order Tracking Firebase Function/functions/test/driver_program/rules.test.js`
- Modify: `Order Tracking Firebase Function/functions/package.json`
- Modify: `Order Tracking Firebase Function/functions/.eslintignore` (créer si absent)

**Interfaces:**
- Consumes: rien
- Produces: `npm test` exécutable ; module `rules.js` requerrable

- [ ] **Step 1: Sauvegarder les deux dossiers hors git**

Ces dossiers n'ont aucun historique. Cette sauvegarde est faite une seule fois, ici.

```bash
cd "c:/Projet/AUTRE/Nouveau dossier"
cp -r "Order Tracking Firebase Function" "_backup_functions_20260829"
cp -r "Admin Panel" "_backup_admin_panel_20260829"
ls -d _backup_*
```

Attendu : les deux dossiers de sauvegarde existent.

- [ ] **Step 2: Ajouter le script de test**

Dans `functions/package.json`, ajouter une ligne au bloc `scripts` (ne rien retirer) :

```json
    "test": "node --test test/"
```

Aucune dépendance n'est ajoutée : `node:test` est intégré à Node 20 et 22.

- [ ] **Step 3: Exclure les tests du lint de déploiement**

Créer `functions/.eslintignore` :

```
node_modules/
test/
```

Le `predeploy` de `firebase.json` lance `npm run lint`. Sans cette exclusion, un test en cours d'écriture bloquerait un déploiement.

- [ ] **Step 4: Écrire le premier test, qui échoue**

Créer `functions/test/driver_program/rules.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert');
const rules = require('../../products/driver_program/rules');

test('formatDriverCode remplit la sequence sur la largeur demandee', () => {
  assert.strictEqual(rules.formatDriverCode('VT-LVR-{seq:6}', 42), 'VT-LVR-000042');
});
```

- [ ] **Step 5: Lancer le test et vérifier qu'il échoue**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Order Tracking Firebase Function/functions"
npm test
```

Attendu : ÉCHEC, `Cannot find module '../../products/driver_program/rules'`.

- [ ] **Step 6: Créer le module minimal**

Créer `functions/products/driver_program/rules.js` :

```js
'use strict';

/**
 * Formate un identifiant de sequence selon un gabarit configure.
 * Gabarit attendu : une occurrence de {seq:N}, N etant la largeur.
 */
function formatDriverCode(template, sequence) {
  const match = /\{seq:(\d+)\}/.exec(template);
  if (match === null) {
    throw new Error('Gabarit de code invalide : ' + template);
  }
  const width = parseInt(match[1], 10);
  const digits = String(sequence);
  if (digits.length > width) {
    throw new Error('Sequence ' + sequence + ' trop grande pour une largeur de ' + width);
  }
  let padded = digits;
  while (padded.length < width) {
    padded = '0' + padded;
  }
  return template.replace(match[0], padded);
}

module.exports = { formatDriverCode: formatDriverCode };
```

- [ ] **Step 7: Lancer le test et vérifier qu'il passe**

```bash
npm test
```

Attendu : 1 test, 1 succès.

- [ ] **Step 8: Vérifier que le lint passe**

```bash
npm run lint
```

Attendu : aucune erreur. Si le lint échoue, le déploiement sera impossible plus tard — corriger maintenant.

- [ ] **Step 9: Commit**

`Order Tracking Firebase Function/` n'est pas un dépôt git. Le suivi se fait dans `customer`.

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git add docs/superpowers/plans/2026-08-29-portail-livreur-noyau-backend.md
git commit -m "plan: noyau backend du portail livreur"
```

---

### Task 2: Format du code livreur — cas limites

**Files:**
- Modify: `functions/products/driver_program/rules.js`
- Test: `functions/test/driver_program/rules.test.js`

**Interfaces:**
- Consumes: `formatDriverCode(template, sequence)` de la tâche 1
- Produces: `formatDriverCode` durci, utilisé par `store.allocateSequence` en tâche 6

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `rules.test.js` :

```js
test('formatDriverCode accepte le gabarit de parrainage', () => {
  assert.strictEqual(rules.formatDriverCode('VT-REF-{seq:6}', 1), 'VT-REF-000001');
});

test('formatDriverCode refuse un gabarit sans marqueur de sequence', () => {
  assert.throws(() => rules.formatDriverCode('VT-LVR-000001', 1), /Gabarit de code invalide/);
});

test('formatDriverCode refuse une sequence plus large que le gabarit', () => {
  assert.throws(() => rules.formatDriverCode('VT-LVR-{seq:3}', 1234), /trop grande/);
});

test('formatDriverCode accepte la borne exacte du gabarit', () => {
  assert.strictEqual(rules.formatDriverCode('VT-LVR-{seq:3}', 999), 'VT-LVR-999');
});
```

- [ ] **Step 2: Lancer les tests**

```bash
npm test
```

Attendu : les 4 nouveaux tests **passent déjà** — l'implémentation de la tâche 1 les couvre. C'est le résultat recherché : ces tests verrouillent le comportement contre une régression future. Si l'un échoue, corriger `rules.js`.

- [ ] **Step 3: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "test: verrouille les cas limites du format de code livreur"
```

---

### Task 3: Correction du test théorique

Le corrigé ne doit jamais quitter le backend. Cette fonction est le seul endroit qui le lit.

**Files:**
- Modify: `functions/products/driver_program/rules.js`
- Test: `functions/test/driver_program/rules.test.js`

**Interfaces:**
- Consumes: rien
- Produces: `gradeTheoryTest(questions, answers, settings) -> { score, total, passed }` où `questions` est un tableau de `{ id, correctIndex }`, `answers` un tableau de `{ questionId, choiceIndex }`, `settings` un objet portant `theoryPassScore` et `theoryTotal`. Utilisé par `v1_submitTheoryTest` en tâche 9.

- [ ] **Step 1: Écrire les tests qui échouent**

```js
const QUESTIONS = [
  { id: 'q1', correctIndex: 0 },
  { id: 'q2', correctIndex: 2 },
  { id: 'q3', correctIndex: 1 }
];
const SETTINGS = { theoryPassScore: 2, theoryTotal: 3 };

test('gradeTheoryTest compte les bonnes reponses', () => {
  const answers = [
    { questionId: 'q1', choiceIndex: 0 },
    { questionId: 'q2', choiceIndex: 2 },
    { questionId: 'q3', choiceIndex: 0 }
  ];
  const r = rules.gradeTheoryTest(QUESTIONS, answers, SETTINGS);
  assert.strictEqual(r.score, 2);
  assert.strictEqual(r.total, 3);
  assert.strictEqual(r.passed, true);
});

test('gradeTheoryTest echoue sous le seuil', () => {
  const answers = [{ questionId: 'q1', choiceIndex: 0 }];
  const r = rules.gradeTheoryTest(QUESTIONS, answers, SETTINGS);
  assert.strictEqual(r.score, 1);
  assert.strictEqual(r.passed, false);
});

test('gradeTheoryTest compte zero pour une question non repondue', () => {
  const r = rules.gradeTheoryTest(QUESTIONS, [], SETTINGS);
  assert.strictEqual(r.score, 0);
  assert.strictEqual(r.passed, false);
});

test('gradeTheoryTest ignore une reponse a une question hors sujet', () => {
  const answers = [
    { questionId: 'q1', choiceIndex: 0 },
    { questionId: 'inconnue', choiceIndex: 0 }
  ];
  const r = rules.gradeTheoryTest(QUESTIONS, answers, SETTINGS);
  assert.strictEqual(r.score, 1);
});

test('gradeTheoryTest ne compte pas deux fois une question repondue en double', () => {
  const answers = [
    { questionId: 'q1', choiceIndex: 0 },
    { questionId: 'q1', choiceIndex: 0 }
  ];
  const r = rules.gradeTheoryTest(QUESTIONS, answers, SETTINGS);
  assert.strictEqual(r.score, 1);
});

test('gradeTheoryTest applique le seuil reel du brief : 24 sur 30', () => {
  const questions = [];
  const answers = [];
  for (let i = 0; i < 30; i++) {
    questions.push({ id: 'q' + i, correctIndex: 1 });
    answers.push({ questionId: 'q' + i, choiceIndex: i < 24 ? 1 : 0 });
  }
  const r = rules.gradeTheoryTest(questions, answers, { theoryPassScore: 24, theoryTotal: 30 });
  assert.strictEqual(r.score, 24);
  assert.strictEqual(r.passed, true);
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

Attendu : ÉCHEC, `rules.gradeTheoryTest is not a function`.

- [ ] **Step 3: Implémenter**

Ajouter à `rules.js`, avant `module.exports` :

```js
/**
 * Corrige un test theorique. Fonction pure : c'est le seul endroit ou le
 * corrige est lu, et il ne quitte jamais le backend.
 */
function gradeTheoryTest(questions, answers, settings) {
  const correctById = {};
  questions.forEach((q) => {
    correctById[q.id] = q.correctIndex;
  });

  const seen = {};
  let score = 0;
  answers.forEach((a) => {
    if (seen[a.questionId] === true) {
      return;
    }
    seen[a.questionId] = true;
    if (correctById[a.questionId] === undefined) {
      return;
    }
    if (correctById[a.questionId] === a.choiceIndex) {
      score += 1;
    }
  });

  return {
    score: score,
    total: questions.length,
    passed: score >= settings.theoryPassScore
  };
}
```

Et l'ajouter à l'export :

```js
module.exports = {
  formatDriverCode: formatDriverCode,
  gradeTheoryTest: gradeTheoryTest
};
```

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

Attendu : tous les tests passent.

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: correction du test theorique cote serveur"
```

---

### Task 4: Checklist d'activation — les neuf conditions

**Files:**
- Modify: `functions/products/driver_program/rules.js`
- Test: `functions/test/driver_program/rules.test.js`

**Interfaces:**
- Consumes: rien
- Produces: `computeActivation(dossier, settings) -> { identity, documents, training, theoryTest, practicalTest, certification, agreement, payoutAccount, profileComplete }`, neuf booléens. `dossier` est un objet `{ profile, documents, training, signatures, user }`. Utilisé par `computeStatus` en tâche 5 et par `v1_recomputeStatus` en tâche 10.

- [ ] **Step 1: Écrire les tests qui échouent**

```js
const SET9 = {
  requiredDocumentTypes: ['id_proof', 'driving_license'],
  identityDocumentType: 'id_proof',
  theoryPassScore: 24,
  practicalPassScore: 16,
  requiredAgreements: ['partnership']
};

function dossierComplet() {
  return {
    profile: {
      firstName: 'Amani', lastName: 'Kabila', phone: '+243900000000',
      address: 'Goma', primaryZoneId: 'goma', vehicleType: 'moto'
    },
    documents: [
      { typeId: 'id_proof', status: 'APPROVED' },
      { typeId: 'driving_license', status: 'APPROVED' }
    ],
    training: {
      modules: [{ moduleId: 'm1', completedAt: 1 }],
      theory: { bestScore: 27 },
      practical: { score: 18 },
      certifiedAt: 123
    },
    requiredModuleIds: ['m1'],
    signatures: [{ documentType: 'partnership', documentVersion: 3 }],
    agreementVersions: { partnership: 3 },
    user: { userBankDetails: { accountNumber: '1' } }
  };
}

test('computeActivation valide un dossier complet', () => {
  const a = rules.computeActivation(dossierComplet(), SET9);
  Object.keys(a).forEach((k) => {
    assert.strictEqual(a[k], true, 'condition fausse : ' + k);
  });
});

test('computeActivation refuse une piece non approuvee', () => {
  const d = dossierComplet();
  d.documents[1].status = 'PENDING';
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(a.documents, false);
  assert.strictEqual(a.identity, true);
});

test('computeActivation refuse une piece expiree', () => {
  const d = dossierComplet();
  d.documents[0].status = 'EXPIRED';
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(a.identity, false);
  assert.strictEqual(a.documents, false);
});

test('computeActivation refuse un score theorique insuffisant', () => {
  const d = dossierComplet();
  d.training.theory.bestScore = 23;
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(a.theoryTest, false);
});

test('computeActivation refuse une note pratique insuffisante', () => {
  const d = dossierComplet();
  d.training.practical.score = 15;
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(a.practicalTest, false);
});

test('computeActivation refuse une signature de version perimee', () => {
  const d = dossierComplet();
  d.agreementVersions.partnership = 4;
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(a.agreement, false);
});

test('computeActivation refuse un module requis non termine', () => {
  const d = dossierComplet();
  d.training.modules[0].completedAt = null;
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(a.training, false);
});

test('computeActivation refuse un profil incomplet', () => {
  const d = dossierComplet();
  d.profile.primaryZoneId = '';
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(a.profileComplete, false);
});

test('computeActivation refuse un compte de paiement absent', () => {
  const d = dossierComplet();
  d.user.userBankDetails = null;
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(a.payoutAccount, false);
});

test('computeActivation refuse une certification absente', () => {
  const d = dossierComplet();
  d.training.certifiedAt = null;
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(a.certification, false);
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

Attendu : ÉCHEC, `rules.computeActivation is not a function`.

- [ ] **Step 3: Implémenter**

Ajouter à `rules.js` :

```js
const PROFILE_REQUIRED_FIELDS = [
  'firstName', 'lastName', 'phone', 'address', 'primaryZoneId', 'vehicleType'
];

function documentApproved(documents, typeId) {
  let ok = false;
  documents.forEach((d) => {
    if (d.typeId === typeId && d.status === 'APPROVED') {
      ok = true;
    }
  });
  return ok;
}

/**
 * Calcule les neuf conditions d'activation du §11. Fonction pure :
 * le meme dossier produit toujours la meme checklist.
 */
function computeActivation(dossier, settings) {
  const documents = dossier.documents || [];
  const training = dossier.training || {};
  const theory = training.theory || {};
  const practical = training.practical || {};
  const modules = training.modules || [];
  const profile = dossier.profile || {};
  const user = dossier.user || {};
  const signatures = dossier.signatures || [];
  const agreementVersions = dossier.agreementVersions || {};
  const requiredModuleIds = dossier.requiredModuleIds || [];

  const completedModuleIds = {};
  modules.forEach((m) => {
    if (m.completedAt !== null && m.completedAt !== undefined) {
      completedModuleIds[m.moduleId] = true;
    }
  });

  const signedVersions = {};
  signatures.forEach((s) => {
    signedVersions[s.documentType] = s.documentVersion;
  });

  let documentsOk = true;
  settings.requiredDocumentTypes.forEach((typeId) => {
    if (documentApproved(documents, typeId) === false) {
      documentsOk = false;
    }
  });

  let trainingOk = true;
  requiredModuleIds.forEach((id) => {
    if (completedModuleIds[id] !== true) {
      trainingOk = false;
    }
  });

  let agreementOk = true;
  settings.requiredAgreements.forEach((type) => {
    if (signedVersions[type] !== agreementVersions[type]) {
      agreementOk = false;
    }
  });

  let profileOk = true;
  PROFILE_REQUIRED_FIELDS.forEach((field) => {
    const v = profile[field];
    if (v === null || v === undefined || v === '') {
      profileOk = false;
    }
  });

  const bank = user.userBankDetails;
  const payoutOk = bank !== null && bank !== undefined && Object.keys(bank).length > 0;

  return {
    identity: documentApproved(documents, settings.identityDocumentType),
    documents: documentsOk,
    training: trainingOk,
    theoryTest: (theory.bestScore || 0) >= settings.theoryPassScore,
    practicalTest: (practical.score || 0) >= settings.practicalPassScore,
    certification: training.certifiedAt !== null && training.certifiedAt !== undefined,
    agreement: agreementOk,
    payoutAccount: payoutOk,
    profileComplete: profileOk
  };
}
```

Ajouter `computeActivation: computeActivation` à `module.exports`.

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: checklist d'activation a neuf conditions"
```

---

### Task 5: Calcul du statut

**Files:**
- Modify: `functions/products/driver_program/rules.js`
- Test: `functions/test/driver_program/rules.test.js`

**Interfaces:**
- Consumes: `computeActivation` de la tâche 4
- Produces: `computeStatus(dossier, activation, settings) -> string`, une valeur de `rules.STATUSES`. Utilisé par `v1_recomputeStatus` en tâche 10.

- [ ] **Step 1: Écrire les tests qui échouent**

```js
test('computeStatus : dossier vide reste en candidature', () => {
  const d = { documents: [], training: {}, profile: {}, user: {} };
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'CANDIDATURE');
});

test('computeStatus : pieces deposees mais non validees', () => {
  const d = dossierComplet();
  d.documents = [
    { typeId: 'id_proof', status: 'PENDING' },
    { typeId: 'driving_license', status: 'PENDING' }
  ];
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'DOSSIER_A_VERIFIER');
});

test('computeStatus : pieces validees, formation non commencee', () => {
  const d = dossierComplet();
  d.training = { modules: [], theory: {}, practical: {} };
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'DOCUMENTS_VALIDES');
});

test('computeStatus : formation terminee, test non reussi', () => {
  const d = dossierComplet();
  d.training.theory = { bestScore: 10 };
  d.training.practical = {};
  d.training.certifiedAt = null;
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'TEST');
});

test('computeStatus : test reussi, simulation non notee', () => {
  const d = dossierComplet();
  d.training.practical = {};
  d.training.certifiedAt = null;
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'SIMULATION_PRATIQUE');
});

test('computeStatus : certifie, accord non signe', () => {
  const d = dossierComplet();
  d.signatures = [];
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'CERTIFIE');
});

test('computeStatus : accord signe, compte de paiement manquant', () => {
  const d = dossierComplet();
  d.user.userBankDetails = null;
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'PENDING_ACTIVATION');
});

test('computeStatus : tout est reuni', () => {
  const d = dossierComplet();
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'ACTIVE');
});

test('computeStatus : un statut administratif prime sur tout', () => {
  const d = dossierComplet();
  d.adminStatus = 'SUSPENDU';
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'SUSPENDU');
});

test('computeStatus : un rejet administratif prime sur tout', () => {
  const d = dossierComplet();
  d.adminStatus = 'REJETE';
  const a = rules.computeActivation(d, SET9);
  assert.strictEqual(rules.computeStatus(d, a, SET9), 'REJETE');
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

Attendu : ÉCHEC, `rules.computeStatus is not a function`.

- [ ] **Step 3: Implémenter**

Ajouter à `rules.js` :

```js
const STATUSES = {
  CANDIDATURE: 'CANDIDATURE',
  DOSSIER_A_VERIFIER: 'DOSSIER_A_VERIFIER',
  DOCUMENTS_VALIDES: 'DOCUMENTS_VALIDES',
  FORMATION: 'FORMATION',
  TEST: 'TEST',
  SIMULATION_PRATIQUE: 'SIMULATION_PRATIQUE',
  CERTIFIE: 'CERTIFIE',
  ACCORD_SIGNE: 'ACCORD_SIGNE',
  PENDING_ACTIVATION: 'PENDING_ACTIVATION',
  ACTIVE: 'ACTIVE',
  REJETE: 'REJETE',
  SUSPENDU: 'SUSPENDU'
};

/**
 * Determine le statut a partir des faits enregistres. Fonction pure et
 * idempotente : le statut n'est jamais « avance » par une transition, il est
 * toujours recalcule depuis le dossier. Un dossier qui regresse (piece expiree)
 * revient donc naturellement en arriere.
 */
function computeStatus(dossier, activation, settings) {
  if (dossier.adminStatus === STATUSES.SUSPENDU || dossier.adminStatus === STATUSES.REJETE) {
    return dossier.adminStatus;
  }

  const allTrue = Object.keys(activation).every((k) => activation[k] === true);
  if (allTrue === true) {
    return STATUSES.ACTIVE;
  }
  if (activation.agreement === true) {
    return STATUSES.PENDING_ACTIVATION;
  }
  if (activation.certification === true) {
    return STATUSES.CERTIFIE;
  }
  if (activation.theoryTest === true) {
    return STATUSES.SIMULATION_PRATIQUE;
  }
  if (activation.training === true) {
    return STATUSES.TEST;
  }
  if (activation.documents === true) {
    const modules = (dossier.training || {}).modules || [];
    return modules.length > 0 ? STATUSES.FORMATION : STATUSES.DOCUMENTS_VALIDES;
  }

  const documents = dossier.documents || [];
  return documents.length > 0 ? STATUSES.DOSSIER_A_VERIFIER : STATUSES.CANDIDATURE;
}
```

Ajouter `computeStatus: computeStatus` et `STATUSES: STATUSES` à `module.exports`.

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: calcul idempotent du statut du dossier"
```

---

### Task 6: Allocation atomique du code livreur, sur émulateur

C'est la seule partie du plan où la concurrence peut produire un doublon. La reprise des 383 comptes du plan 1C allouera 383 codes : cette transaction doit être éprouvée avant, pas pendant.

**Files:**
- Create: `functions/products/driver_program/store.js`
- Create: `functions/test/driver_program/store.test.js`
- Modify: `Order Tracking Firebase Function/firebase.json`

**Interfaces:**
- Consumes: `rules.formatDriverCode` de la tâche 1
- Produces: `allocateSequence(db, counterId) -> Promise<number>` et `allocateDriverCodes(db, settings) -> Promise<{ driverCode, referralCode }>`. Utilisé par `v1_applyAsDriver` en tâche 7.

- [ ] **Step 1: Configurer l'émulateur**

Remplacer le contenu de `Order Tracking Firebase Function/firebase.json` par :

```json
{
  "functions": {
    "predeploy": [
      "npm --prefix \"$RESOURCE_DIR\" run lint"
    ]
  },
  "firestore": {
    "rules": "firestore.rules"
  },
  "emulators": {
    "firestore": { "port": 8080 },
    "ui": { "enabled": false }
  }
}
```

Créer `Order Tracking Firebase Function/firestore.rules` avec un contenu provisoire, remplacé en tâche 12 :

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} { allow read, write: if false; }
  }
}
```

**Attention :** ce fichier ne doit **jamais** être déployé tel quel — il couperait la production. Le bloc `firestore` de `firebase.json` rend `firebase deploy` capable de le publier. Tous les déploiements de ce plan sont ciblés sur des fonctions ; le déploiement des règles se fait explicitement en tâche 12, avec le contenu définitif.

- [ ] **Step 2: Écrire le test qui échoue**

Créer `functions/test/driver_program/store.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert');

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
const admin = require('firebase-admin');
if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: 'rapyogo-test' });
}
const db = admin.firestore();
const store = require('../../products/driver_program/store');

const SETTINGS = {
  codeFormat: 'VT-LVR-{seq:6}',
  referralCodeFormat: 'VT-REF-{seq:6}'
};

test('allocateSequence rend des entiers successifs', async () => {
  await db.collection('driver_program_counters').doc('t_seq').delete();
  const a = await store.allocateSequence(db, 't_seq');
  const b = await store.allocateSequence(db, 't_seq');
  assert.strictEqual(a, 1);
  assert.strictEqual(b, 2);
});

test('allocateSequence ne produit aucun doublon sous 20 appels concurrents', async () => {
  await db.collection('driver_program_counters').doc('t_conc').delete();
  const calls = [];
  for (let i = 0; i < 20; i++) {
    calls.push(store.allocateSequence(db, 't_conc'));
  }
  const results = await Promise.all(calls);
  const uniques = {};
  results.forEach((n) => { uniques[n] = true; });
  assert.strictEqual(Object.keys(uniques).length, 20, 'doublon detecte : ' + results.join(','));
});

test('allocateDriverCodes produit les deux codes au format configure', async () => {
  await db.collection('driver_program_counters').doc('driver_code').delete();
  const codes = await store.allocateDriverCodes(db, SETTINGS);
  assert.match(codes.driverCode, /^VT-LVR-\d{6}$/);
  assert.match(codes.referralCode, /^VT-REF-\d{6}$/);
});
```

- [ ] **Step 3: Lancer l'émulateur, puis le test, et vérifier qu'il échoue**

Dans un premier terminal :

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Order Tracking Firebase Function"
firebase emulators:start --only firestore --project rapyogo-test
```

Dans un second :

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Order Tracking Firebase Function/functions"
npm test
```

Attendu : ÉCHEC, `Cannot find module '../../products/driver_program/store'`.

- [ ] **Step 4: Implémenter**

Créer `functions/products/driver_program/store.js` :

```js
'use strict';

const rules = require('./rules');

/**
 * Incremente un compteur et rend sa nouvelle valeur, en transaction.
 * C'est la seule garantie d'unicite des identifiants livreur : deux
 * candidatures simultanees ne peuvent pas obtenir le meme numero.
 */
function allocateSequence(db, counterId) {
  const ref = db.collection('driver_program_counters').doc(counterId);
  return db.runTransaction((tx) => {
    return tx.get(ref).then((snap) => {
      const current = snap.exists === true ? (snap.data().value || 0) : 0;
      const next = current + 1;
      tx.set(ref, { value: next }, { merge: true });
      return next;
    });
  });
}

/**
 * Alloue le code livreur et le code de parrainage a partir d'une seule
 * sequence : les deux codes portent donc le meme numero, ce qui facilite
 * le rapprochement au support.
 */
function allocateDriverCodes(db, settings) {
  return allocateSequence(db, 'driver_code').then((seq) => {
    return {
      driverCode: rules.formatDriverCode(settings.codeFormat, seq),
      referralCode: rules.formatDriverCode(settings.referralCodeFormat, seq)
    };
  });
}

module.exports = {
  allocateSequence: allocateSequence,
  allocateDriverCodes: allocateDriverCodes
};
```

- [ ] **Step 5: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

Attendu : tous les tests passent, dont celui des 20 appels concurrents. **Si un doublon apparaît, ne pas continuer** — la transaction est fausse et la reprise du plan 1C produirait des identifiants en double.

- [ ] **Step 6: Lint**

```bash
npm run lint
```

- [ ] **Step 7: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: allocation atomique des identifiants livreur"
```

---

### Task 7: Lecture du dossier et journalisation

**Files:**
- Modify: `functions/products/driver_program/store.js`
- Test: `functions/test/driver_program/store.test.js`

**Interfaces:**
- Consumes: `allocateSequence` de la tâche 6
- Produces: `loadDossier(db, uid) -> Promise<dossier>` au format attendu par `rules.computeActivation` ; `appendHistory(db, entry) -> Promise` ; `appendAudit(db, entry) -> Promise`. Utilisés par toutes les callables des tâches 8 à 11.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `store.test.js` :

```js
test('loadDossier assemble les six sources en un seul objet', async () => {
  const uid = 'u_test_dossier';
  await db.collection('driver_program').doc(uid).set({
    driverCode: 'VT-LVR-000001',
    profile: { firstName: 'Amani', primaryZoneId: 'goma' }
  });
  await db.collection('users').doc(uid).set({ userBankDetails: { accountNumber: '1' } });
  await db.collection('driver_documents').add({ driverId: uid, typeId: 'id_proof', status: 'APPROVED' });
  await db.collection('driver_training').doc(uid).set({ theory: { bestScore: 27 } });
  await db.collection('driver_signatures').add({ driverId: uid, documentType: 'partnership', documentVersion: 3 });

  await db.collection('driver_agreements').doc('partnership').set({ version: 3, hash: 'abc' });

  const d = await store.loadDossier(db, uid);
  assert.strictEqual(d.profile.firstName, 'Amani');
  assert.strictEqual(d.user.userBankDetails.accountNumber, '1');
  assert.strictEqual(d.documents.length, 1);
  assert.strictEqual(d.training.theory.bestScore, 27);
  assert.strictEqual(d.signatures.length, 1);
  assert.strictEqual(d.agreementVersions.partnership, 3,
    'sans la version en vigueur, la condition « accord signe » serait toujours fausse');
});

test('loadDossier rend un dossier vide et non nul pour un inconnu', async () => {
  const d = await store.loadDossier(db, 'u_inexistant');
  assert.deepStrictEqual(d.documents, []);
  assert.deepStrictEqual(d.signatures, []);
  assert.deepStrictEqual(d.profile, {});
});

test('appendHistory ecrit une ligne horodatee', async () => {
  await store.appendHistory(db, {
    driverId: 'u_hist', driverCode: 'VT-LVR-000002',
    from: 'CANDIDATURE', to: 'DOSSIER_A_VERIFIER',
    actorId: 'u_hist', actorType: 'driver', reason: ''
  });
  const s = await db.collection('driver_program_history').where('driverId', '==', 'u_hist').get();
  assert.strictEqual(s.size, 1);
  assert.strictEqual(s.docs[0].data().to, 'DOSSIER_A_VERIFIER');
  assert.ok(s.docs[0].data().at);
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

Attendu : ÉCHEC, `store.loadDossier is not a function`.

- [ ] **Step 3: Implémenter**

Ajouter à `store.js`, avant `module.exports` :

```js
const admin = require('firebase-admin');

/**
 * Assemble le dossier complet d'un livreur a partir des collections qui le
 * composent. Les sept lectures partent ensemble : aucune ne depend d'une autre.
 *
 * agreementVersions porte la version EN VIGUEUR de chaque accord. C'est ce qui
 * permet a computeActivation de comparer la version signee a la version
 * courante : sans cette lecture, la condition « accord signe » serait toujours
 * fausse et aucun livreur ne pourrait jamais etre active.
 */
function loadDossier(db, uid) {
  return Promise.all([
    db.collection('driver_program').doc(uid).get(),
    db.collection('users').doc(uid).get(),
    db.collection('driver_documents').where('driverId', '==', uid).get(),
    db.collection('driver_training').doc(uid).get(),
    db.collection('driver_signatures').where('driverId', '==', uid).get(),
    db.collection('driver_training_modules').where('required', '==', true).where('published', '==', true).get(),
    db.collection('driver_agreements').get()
  ]).then((results) => {
    const program = results[0].exists === true ? results[0].data() : {};
    const user = results[1].exists === true ? results[1].data() : {};
    const documents = results[2].docs.map((d) => Object.assign({ id: d.id }, d.data()));
    const training = results[3].exists === true ? results[3].data() : {};
    const signatures = results[4].docs.map((d) => d.data());
    const requiredModuleIds = results[5].docs.map((d) => d.id);

    const agreementVersions = {};
    results[6].docs.forEach((d) => {
      agreementVersions[d.id] = d.data().version;
    });

    return {
      program: program,
      profile: program.profile || {},
      adminStatus: program.adminStatus || null,
      user: user,
      documents: documents,
      training: training,
      signatures: signatures,
      requiredModuleIds: requiredModuleIds,
      agreementVersions: agreementVersions
    };
  });
}

function appendHistory(db, entry) {
  return db.collection('driver_program_history').add(
    Object.assign({}, entry, { at: admin.firestore.FieldValue.serverTimestamp() })
  );
}

function appendAudit(db, entry) {
  return db.collection('driver_audit_log').add(
    Object.assign({}, entry, { at: admin.firestore.FieldValue.serverTimestamp() })
  );
}
```

Ajouter `loadDossier`, `appendHistory` et `appendAudit` à `module.exports`.

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: lecture du dossier livreur et journalisation"
```

---

### Task 8: `v1_recomputeStatus`, le cœur du système

Toutes les autres fonctions l'appellent. Elle est écrite avant elles.

**Files:**
- Create: `functions/products/driver_program/callables.js`
- Test: `functions/test/driver_program/store.test.js`

**Interfaces:**
- Consumes: `rules.computeActivation`, `rules.computeStatus`, `store.loadDossier`, `store.appendHistory`
- Produces: `recomputeStatus(db, uid, actor) -> Promise<{ status, activation, changed }>`. Appelée par toutes les callables des tâches 9 à 11 et par les callables admin de la tâche 13.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `store.test.js` :

```js
const program = require('../../products/driver_program/callables');
const ACTOR = { id: 'sys', type: 'system' };

test('recomputeStatus ecrit le statut calcule sur le dossier', async () => {
  const uid = 'u_recompute';
  await db.collection('driver_program').doc(uid).set({
    driverCode: 'VT-LVR-000009', profile: {}, status: 'CANDIDATURE'
  });
  await db.collection('driver_program_settings').doc('config').set({
    requiredDocumentTypes: ['id_proof'], identityDocumentType: 'id_proof',
    theoryPassScore: 24, practicalPassScore: 16, requiredAgreements: ['partnership'],
    codeFormat: 'VT-LVR-{seq:6}', referralCodeFormat: 'VT-REF-{seq:6}'
  });

  const r = await program.recomputeStatus(db, uid, ACTOR);
  assert.strictEqual(r.status, 'CANDIDATURE');
  assert.strictEqual(r.activation.documents, false);
});

test('recomputeStatus est idempotent : deux appels, une seule ligne d historique', async () => {
  const uid = 'u_idem';
  await db.collection('driver_program').doc(uid).set({
    driverCode: 'VT-LVR-000010', profile: {}, status: 'CANDIDATURE'
  });
  await db.collection('driver_documents').add({ driverId: uid, typeId: 'id_proof', status: 'PENDING' });

  await program.recomputeStatus(db, uid, ACTOR);
  await program.recomputeStatus(db, uid, ACTOR);

  const h = await db.collection('driver_program_history').where('driverId', '==', uid).get();
  assert.strictEqual(h.size, 1, 'une transition sans changement ne doit rien ecrire');
});

test('recomputeStatus ne met jamais users.isActive a false', async () => {
  const uid = 'u_jamais_false';
  await db.collection('users').doc(uid).set({ isActive: true, orderRequestData: ['course_en_cours'] });
  await db.collection('driver_program').doc(uid).set({
    driverCode: 'VT-LVR-000011', profile: {}, status: 'ACTIVE'
  });

  await program.recomputeStatus(db, uid, ACTOR);

  const u = await db.collection('users').doc(uid).get();
  assert.strictEqual(u.data().isActive, true);
  assert.deepStrictEqual(u.data().orderRequestData, ['course_en_cours'],
    'la course en cours ne doit jamais etre effacee');
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

Attendu : ÉCHEC, `Cannot find module '../../products/driver_program/callables'`.

- [ ] **Step 3: Implémenter**

Créer `functions/products/driver_program/callables.js` :

```js
'use strict';

const admin = require('firebase-admin');
const rules = require('./rules');
const store = require('./store');

function loadSettings(db) {
  return db.collection('driver_program_settings').doc('config').get().then((snap) => {
    if (snap.exists !== true) {
      throw new Error('Configuration du programme absente : driver_program_settings/config');
    }
    return snap.data();
  });
}

/**
 * Recalcule la checklist et le statut d'un dossier, ecrit l'historique si le
 * statut change, et met a jour le miroir dans users a l'activation.
 *
 * Idempotente : appelable autant de fois que voulu sans effet de bord.
 */
function recomputeStatus(db, uid, actor) {
  let settings = null;
  let dossier = null;
  let activation = null;
  let status = null;
  let previousStatus = null;

  return loadSettings(db).then((s) => {
    settings = s;
    return store.loadDossier(db, uid);
  }).then((d) => {
    dossier = d;
    previousStatus = d.program.status || null;
    activation = rules.computeActivation(dossier, settings);
    status = rules.computeStatus(dossier, activation, settings);

    const patch = { activation: activation, status: status };
    if (status === rules.STATUSES.ACTIVE && previousStatus !== rules.STATUSES.ACTIVE) {
      patch.dates = Object.assign({}, dossier.program.dates || {}, {
        activatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
    return db.collection('driver_program').doc(uid).set(patch, { merge: true });
  }).then(() => {
    if (status === previousStatus) {
      return null;
    }
    return store.appendHistory(db, {
      driverId: uid,
      driverCode: dossier.program.driverCode || null,
      from: previousStatus,
      to: status,
      actorId: actor.id,
      actorType: actor.type,
      reason: ''
    });
  }).then(() => {
    if (status !== rules.STATUSES.ACTIVE) {
      return null;
    }
    // update() cible, jamais set() : un set sans merge effacerait
    // orderRequestData et inProgressOrderID, donc une course en cours.
    return db.collection('users').doc(uid).update({
      isActive: true,
      isDocumentVerify: true
    }).catch((e) => {
      // Le document users peut ne pas exister pour une candidature web pure.
      console.log('[DRIVER_PROGRAM] miroir users impossible pour ' + uid + ' : ' + e.message);
      return null;
    });
  }).then(() => {
    return { status: status, activation: activation, changed: status !== previousStatus };
  });
}

module.exports = {
  loadSettings: loadSettings,
  recomputeStatus: recomputeStatus
};
```

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

Attendu : tous les tests passent, **en particulier celui qui vérifie qu'`orderRequestData` survit**. C'est le test qui protège contre la perte d'une course en cours.

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: recalcul idempotent du statut et miroir vers users"
```

---

### Task 9: Candidature et profil

**Files:**
- Modify: `functions/products/driver_program/callables.js`
- Test: `functions/test/driver_program/store.test.js`

**Interfaces:**
- Consumes: `store.allocateDriverCodes`, `recomputeStatus`
- Produces: `v1_applyAsDriver` et `v1_updateProfile`, callables Firebase. Consommées par le portail Laravel du plan 1B.

- [ ] **Step 1: Écrire les tests qui échouent**

Les callables sont testées par leur implémentation interne, extraite pour être appelable sans contexte Firebase.

```js
test('applyAsDriver cree un dossier avec un code alloue', async () => {
  const uid = 'u_apply';
  await db.collection('driver_program').doc(uid).delete();
  const r = await program.applyAsDriver(db, uid, {
    firstName: 'Amani', lastName: 'Kabila', phone: '+243900000001',
    address: 'Goma', primaryZoneId: 'goma', vehicleType: 'moto'
  }, null);

  assert.match(r.driverCode, /^VT-LVR-\d{6}$/);
  const d = await db.collection('driver_program').doc(uid).get();
  assert.strictEqual(d.data().profile.firstName, 'Amani');
  assert.strictEqual(d.data().level, 1);
  assert.strictEqual(typeof d.data().qrToken, 'string');
  assert.strictEqual(d.data().qrToken.length, 32);
});

test('applyAsDriver refuse une seconde candidature', async () => {
  const uid = 'u_apply_double';
  await db.collection('driver_program').doc(uid).delete();
  await program.applyAsDriver(db, uid, { firstName: 'A' }, null);
  await assert.rejects(
    () => program.applyAsDriver(db, uid, { firstName: 'A' }, null),
    /dossier existe deja/
  );
});

test('updateProfile ignore les champs hors liste blanche', async () => {
  const uid = 'u_profil';
  await db.collection('driver_program').doc(uid).delete();
  await program.applyAsDriver(db, uid, { firstName: 'Amani' }, null);
  await program.updateProfile(db, uid, { firstName: 'Bob', level: 3, status: 'ACTIVE' });

  const d = await db.collection('driver_program').doc(uid).get();
  assert.strictEqual(d.data().profile.firstName, 'Bob');
  assert.strictEqual(d.data().level, 1, 'le niveau ne doit pas etre modifiable par le livreur');
  assert.notStrictEqual(d.data().status, 'ACTIVE');
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

Attendu : ÉCHEC, `program.applyAsDriver is not a function`.

- [ ] **Step 3: Implémenter**

Ajouter à `callables.js` :

```js
const crypto = require('crypto');
const functions = require('firebase-functions/v1');

const PROFILE_WHITELIST = [
  'firstName', 'lastName', 'photoURL', 'phone', 'email', 'address',
  'primaryZoneId', 'secondaryZoneIds', 'vehicleType'
];

function pickProfile(input) {
  const clean = {};
  PROFILE_WHITELIST.forEach((k) => {
    if (input[k] !== undefined) {
      clean[k] = input[k];
    }
  });
  return clean;
}

function applyAsDriver(db, uid, profileInput, referralCode) {
  let settings = null;
  return loadSettings(db).then((s) => {
    settings = s;
    return db.collection('driver_program').doc(uid).get();
  }).then((snap) => {
    if (snap.exists === true) {
      throw new Error('Un dossier existe deja pour ce compte.');
    }
    return store.allocateDriverCodes(db, settings);
  }).then((codes) => {
    return db.collection('driver_program').doc(uid).set({
      driverCode: codes.driverCode,
      referralCode: codes.referralCode,
      referredBy: referralCode || null,
      level: 1,
      status: rules.STATUSES.CANDIDATURE,
      profile: pickProfile(profileInput),
      qrToken: crypto.randomBytes(16).toString('hex'),
      activation: {},
      dates: { appliedAt: admin.firestore.FieldValue.serverTimestamp() }
    }).then(() => codes);
  }).then((codes) => {
    return recomputeStatus(db, uid, { id: uid, type: 'driver' }).then(() => codes);
  });
}

function updateProfile(db, uid, profileInput) {
  const clean = pickProfile(profileInput);
  const patch = {};
  Object.keys(clean).forEach((k) => {
    patch['profile.' + k] = clean[k];
  });
  if (Object.keys(patch).length === 0) {
    return recomputeStatus(db, uid, { id: uid, type: 'driver' });
  }
  return db.collection('driver_program').doc(uid).update(patch).then(() => {
    return recomputeStatus(db, uid, { id: uid, type: 'driver' });
  });
}

function requireAuth(context) {
  if (context.auth === null || context.auth === undefined) {
    throw new functions.https.HttpsError('unauthenticated', 'Connexion requise.');
  }
  return context.auth.uid;
}

const v1_applyAsDriver = functions.https.onCall((data, context) => {
  const uid = requireAuth(context);
  return applyAsDriver(admin.firestore(), uid, data.profile || {}, data.referralCode || null)
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});

const v1_updateProfile = functions.https.onCall((data, context) => {
  const uid = requireAuth(context);
  return updateProfile(admin.firestore(), uid, data.profile || {})
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
```

Ajouter à `module.exports` : `applyAsDriver`, `updateProfile`, `requireAuth`, `pickProfile`, `v1_applyAsDriver`, `v1_updateProfile`.

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: candidature et mise a jour de profil"
```

---

### Task 10: Documents, formation et test théorique

**Files:**
- Modify: `functions/products/driver_program/callables.js`
- Test: `functions/test/driver_program/store.test.js`

**Interfaces:**
- Consumes: `rules.gradeTheoryTest`, `recomputeStatus`
- Produces: `v1_submitDocument`, `v1_completeTrainingModule`, `v1_startTheoryTest`, `v1_submitTheoryTest`

- [ ] **Step 1: Écrire les tests qui échouent**

```js
test('submitDocument enregistre un depot en PENDING et versionne un re-depot', async () => {
  const uid = 'u_docs';
  await program.submitDocument(db, uid, 'id_proof', 'https://s/f1.jpg', null);
  await program.submitDocument(db, uid, 'id_proof', 'https://s/f2.jpg', null);
  const s = await db.collection('driver_documents').where('driverId', '==', uid).get();
  const versions = s.docs.map((d) => d.data().version).sort();
  assert.deepStrictEqual(versions, [1, 2]);
  s.docs.forEach((d) => assert.strictEqual(d.data().status, 'PENDING'));
});

test('startTheoryTest ne renvoie jamais le corrige', async () => {
  const uid = 'u_test';
  await db.collection('driver_training_questions').doc('qa').set({
    text: 'Question A', choices: ['x', 'y'], correctIndex: 1, published: true
  });
  const r = await program.startTheoryTest(db, uid);
  r.questions.forEach((q) => {
    assert.strictEqual(q.correctIndex, undefined, 'le corrige ne doit jamais sortir du backend');
    assert.ok(Array.isArray(q.choices));
  });
});

test('submitTheoryTest corrige et enregistre le meilleur score', async () => {
  const uid = 'u_test2';
  await db.collection('driver_training_questions').doc('qb').set({
    text: 'Question B', choices: ['x', 'y'], correctIndex: 1, published: true
  });
  await db.collection('driver_program_settings').doc('config').set({
    theoryPassScore: 1, theoryTotal: 1, theoryMaxAttempts: 3,
    requiredDocumentTypes: [], identityDocumentType: 'id_proof',
    practicalPassScore: 16, requiredAgreements: [],
    codeFormat: 'VT-LVR-{seq:6}', referralCodeFormat: 'VT-REF-{seq:6}'
  }, { merge: true });

  const started = await program.startTheoryTest(db, uid);
  const answers = started.questions.map((q) => ({ questionId: q.id, choiceIndex: 1 }));
  const r = await program.submitTheoryTest(db, uid, started.attemptId, answers);

  assert.strictEqual(r.passed, true);
  const t = await db.collection('driver_training').doc(uid).get();
  assert.strictEqual(t.data().theory.bestScore, r.score);
});

test('submitTheoryTest refuse au-dela du nombre de tentatives', async () => {
  const uid = 'u_test3';
  await db.collection('driver_training').doc(uid).set({ theory: { attempts: 3 } });
  await assert.rejects(() => program.startTheoryTest(db, uid), /tentatives/);
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

- [ ] **Step 3: Implémenter**

Ajouter à `callables.js` :

```js
function submitDocument(db, uid, typeId, frontURL, backURL) {
  return db.collection('driver_documents')
    .where('driverId', '==', uid).where('typeId', '==', typeId).get()
    .then((snap) => {
      return db.collection('driver_documents').add({
        driverId: uid,
        typeId: typeId,
        status: 'PENDING',
        frontURL: frontURL || null,
        backURL: backURL || null,
        version: snap.size + 1,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: null,
        reviewedAt: null,
        reviewedBy: null,
        rejectionReason: null
      });
    }).then(() => {
      return recomputeStatus(db, uid, { id: uid, type: 'driver' });
    });
}

function completeTrainingModule(db, uid, moduleId) {
  return db.collection('driver_training').doc(uid).get().then((snap) => {
    const data = snap.exists === true ? snap.data() : {};
    const modules = data.modules || [];
    let found = false;
    modules.forEach((m) => {
      if (m.moduleId === moduleId) {
        m.completedAt = Date.now();
        found = true;
      }
    });
    if (found === false) {
      modules.push({ moduleId: moduleId, startedAt: Date.now(), completedAt: Date.now() });
    }
    return db.collection('driver_training').doc(uid).set({ modules: modules }, { merge: true });
  }).then(() => {
    return recomputeStatus(db, uid, { id: uid, type: 'driver' });
  });
}

function startTheoryTest(db, uid) {
  let settings = null;
  return loadSettings(db).then((s) => {
    settings = s;
    return db.collection('driver_training').doc(uid).get();
  }).then((snap) => {
    const theory = (snap.exists === true ? snap.data().theory : null) || {};
    const attempts = theory.attempts || 0;
    const max = settings.theoryMaxAttempts || 3;
    if (attempts >= max) {
      throw new Error('Nombre de tentatives epuise (' + max + ').');
    }
    return db.collection('driver_training_questions').where('published', '==', true).get();
  }).then((snap) => {
    const all = snap.docs.map((d) => Object.assign({ id: d.id }, d.data()));
    const wanted = settings.theoryTotal || 30;
    const picked = all.sort(() => Math.random() - 0.5).slice(0, wanted);
    return db.collection('driver_theory_attempts').add({
      driverId: uid,
      questionIds: picked.map((q) => q.id),
      answers: [],
      score: null,
      total: picked.length,
      passed: false,
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      submittedAt: null
    }).then((ref) => {
      return {
        attemptId: ref.id,
        // correctIndex est deliberement absent : le corrige ne sort jamais.
        questions: picked.map((q) => ({ id: q.id, text: q.text, choices: q.choices }))
      };
    });
  });
}

function submitTheoryTest(db, uid, attemptId, answers) {
  let settings = null;
  let attempt = null;
  return loadSettings(db).then((s) => {
    settings = s;
    return db.collection('driver_theory_attempts').doc(attemptId).get();
  }).then((snap) => {
    if (snap.exists !== true || snap.data().driverId !== uid) {
      throw new Error('Tentative introuvable.');
    }
    if (snap.data().submittedAt !== null) {
      throw new Error('Cette tentative a deja ete rendue.');
    }
    attempt = snap.data();
    const reads = attempt.questionIds.map((id) => db.collection('driver_training_questions').doc(id).get());
    return Promise.all(reads);
  }).then((snaps) => {
    const questions = snaps.map((s) => ({ id: s.id, correctIndex: s.data().correctIndex }));
    const result = rules.gradeTheoryTest(questions, answers, settings);
    return db.collection('driver_theory_attempts').doc(attemptId).update({
      answers: answers,
      score: result.score,
      total: result.total,
      passed: result.passed,
      submittedAt: admin.firestore.FieldValue.serverTimestamp()
    }).then(() => result);
  }).then((result) => {
    return db.collection('driver_training').doc(uid).get().then((snap) => {
      const theory = (snap.exists === true ? snap.data().theory : null) || {};
      const best = Math.max(theory.bestScore || 0, result.score);
      const patch = {
        theory: {
          attempts: (theory.attempts || 0) + 1,
          bestScore: best,
          lastAttemptAt: Date.now(),
          passedAt: result.passed === true ? (theory.passedAt || Date.now()) : (theory.passedAt || null)
        }
      };
      return db.collection('driver_training').doc(uid).set(patch, { merge: true }).then(() => result);
    });
  }).then((result) => {
    return recomputeStatus(db, uid, { id: uid, type: 'driver' }).then(() => result);
  });
}

const v1_submitDocument = functions.https.onCall((data, context) => {
  const uid = requireAuth(context);
  return submitDocument(admin.firestore(), uid, data.typeId, data.frontURL, data.backURL)
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});

const v1_completeTrainingModule = functions.https.onCall((data, context) => {
  const uid = requireAuth(context);
  return completeTrainingModule(admin.firestore(), uid, data.moduleId)
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});

const v1_startTheoryTest = functions.https.onCall((data, context) => {
  const uid = requireAuth(context);
  return startTheoryTest(admin.firestore(), uid)
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});

const v1_submitTheoryTest = functions.https.onCall((data, context) => {
  const uid = requireAuth(context);
  return submitTheoryTest(admin.firestore(), uid, data.attemptId, data.answers || [])
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
```

Ajouter les huit noms à `module.exports`.

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

Attendu : tous passent, dont celui qui vérifie que `correctIndex` n'est jamais renvoyé.

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: depot de documents, formation et test theorique"
```

---

### Task 11: Signature électronique

**Files:**
- Modify: `functions/products/driver_program/callables.js`
- Test: `functions/test/driver_program/store.test.js`

**Interfaces:**
- Consumes: `recomputeStatus`
- Produces: `v1_signAgreement`

- [ ] **Step 1: Écrire les tests qui échouent**

```js
test('signAgreement enregistre la preuve complete', async () => {
  const uid = 'u_sign';
  await db.collection('driver_agreements').doc('partnership').set({
    version: 3, title: 'Accord de partenariat', body: 'Texte', hash: 'abc'
  });
  await db.collection('driver_program').doc(uid).set({ driverCode: 'VT-LVR-000020' }, { merge: true });

  await program.signAgreement(db, uid, 'partnership', 3, {
    fullNameTyped: 'Amani Kabila', ip: '1.2.3.4', userAgent: 'Firefox'
  });

  const s = await db.collection('driver_signatures').where('driverId', '==', uid).get();
  assert.strictEqual(s.size, 1);
  const sig = s.docs[0].data();
  assert.strictEqual(sig.documentVersion, 3);
  assert.strictEqual(sig.driverCode, 'VT-LVR-000020');
  assert.strictEqual(sig.ip, '1.2.3.4');
  assert.strictEqual(sig.documentHash, 'abc');
  assert.ok(sig.consentText.length > 0);
  assert.ok(sig.signedAt);
});

test('signAgreement refuse une version perimee', async () => {
  const uid = 'u_sign2';
  await db.collection('driver_agreements').doc('partnership').set({ version: 4, hash: 'def' }, { merge: true });
  await assert.rejects(
    () => program.signAgreement(db, uid, 'partnership', 3, { fullNameTyped: 'A' }),
    /version/
  );
});

test('signAgreement exige un nom saisi', async () => {
  const uid = 'u_sign3';
  await db.collection('driver_agreements').doc('partnership').set({ version: 4, hash: 'def' }, { merge: true });
  await assert.rejects(
    () => program.signAgreement(db, uid, 'partnership', 4, { fullNameTyped: '' }),
    /nom/
  );
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

- [ ] **Step 3: Implémenter**

Ajouter à `callables.js` :

```js
const CONSENT_TEXT = 'En saisissant mon nom et en validant, je reconnais avoir lu et '
  + 'accepte ce document dans son integralite, et je consens a signer par voie electronique.';

function signAgreement(db, uid, documentType, documentVersion, proof) {
  if (proof.fullNameTyped === undefined || String(proof.fullNameTyped).trim() === '') {
    return Promise.reject(new Error('Le nom complet doit etre saisi pour signer.'));
  }
  return Promise.all([
    db.collection('driver_agreements').doc(documentType).get(),
    db.collection('driver_program').doc(uid).get()
  ]).then((results) => {
    const agreement = results[0];
    if (agreement.exists !== true) {
      throw new Error('Document introuvable : ' + documentType);
    }
    if (agreement.data().version !== documentVersion) {
      throw new Error('La version signee (' + documentVersion + ') n est plus la version en vigueur ('
        + agreement.data().version + ').');
    }
    const program = results[1].exists === true ? results[1].data() : {};
    return db.collection('driver_signatures').add({
      driverId: uid,
      driverCode: program.driverCode || null,
      documentType: documentType,
      documentVersion: documentVersion,
      documentHash: agreement.data().hash || null,
      fullNameTyped: String(proof.fullNameTyped).trim(),
      consentText: CONSENT_TEXT,
      signedAt: admin.firestore.FieldValue.serverTimestamp(),
      ip: proof.ip || null,
      userAgent: proof.userAgent || null
    });
  }).then(() => {
    return recomputeStatus(db, uid, { id: uid, type: 'driver' });
  });
}

const v1_signAgreement = functions.https.onCall((data, context) => {
  const uid = requireAuth(context);
  const proof = {
    fullNameTyped: data.fullNameTyped,
    ip: (context.rawRequest && context.rawRequest.ip) ? context.rawRequest.ip : null,
    userAgent: (context.rawRequest && context.rawRequest.headers)
      ? context.rawRequest.headers['user-agent'] : null
  };
  return signAgreement(admin.firestore(), uid, data.documentType, data.documentVersion, proof)
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
```

L'IP et l'appareil sont pris du contexte serveur, **jamais** de ce que le client envoie : une preuve de consentement fournie par le signataire lui-même ne prouve rien.

Ajouter `signAgreement` et `v1_signAgreement` à `module.exports`.

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: signature electronique avec preuve de consentement"
```

---

### Task 12: Règles Firestore des collections neuves

**Files:**
- Modify: `Order Tracking Firebase Function/firestore.rules`
- Create: `functions/test/rules/driver_program.rules.test.js`
- Modify: `functions/package.json`

**Interfaces:**
- Consumes: rien
- Produces: règles publiées sur `rapyogo-2bccd`

- [ ] **Step 1: Installer l'outil de test des règles**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Order Tracking Firebase Function/functions"
npm install --save-dev @firebase/rules-unit-testing@^3.0.4
```

- [ ] **Step 2: Écrire les tests qui échouent**

Créer `functions/test/rules/driver_program.rules.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const rut = require('@firebase/rules-unit-testing');

let env = null;

test.before(async () => {
  env = await rut.initializeTestEnvironment({
    projectId: 'rapyogo-rules-test',
    firestore: { rules: fs.readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 }
  });
});

test.after(async () => { if (env !== null) { await env.cleanup(); } });

test('un livreur lit son propre dossier', async () => {
  const db = env.authenticatedContext('u1').firestore();
  await rut.assertSucceeds(db.collection('driver_program').doc('u1').get());
});

test('un livreur ne lit pas le dossier d un autre', async () => {
  const db = env.authenticatedContext('u1').firestore();
  await rut.assertFails(db.collection('driver_program').doc('u2').get());
});

test('un livreur ne peut pas ecrire son propre niveau', async () => {
  const db = env.authenticatedContext('u1').firestore();
  await rut.assertFails(db.collection('driver_program').doc('u1').set({ level: 3 }, { merge: true }));
});

test('un livreur ne peut pas ecrire son propre statut', async () => {
  const db = env.authenticatedContext('u1').firestore();
  await rut.assertFails(db.collection('driver_program').doc('u1').set({ status: 'ACTIVE' }, { merge: true }));
});

test('personne ne lit la banque de questions', async () => {
  const driver = env.authenticatedContext('u1').firestore();
  const admin = env.authenticatedContext('a1', { role: 'admin' }).firestore();
  await rut.assertFails(driver.collection('driver_training_questions').doc('q1').get());
  await rut.assertFails(admin.collection('driver_training_questions').doc('q1').get());
});

test('un anonyme ne lit rien du programme', async () => {
  const db = env.unauthenticatedContext().firestore();
  await rut.assertFails(db.collection('driver_program').doc('u1').get());
});

test('une signature ne peut etre ni modifiee ni supprimee', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('driver_signatures').doc('s1').set({ driverId: 'u1' });
  });
  const db = env.authenticatedContext('u1').firestore();
  await rut.assertFails(db.collection('driver_signatures').doc('s1').update({ driverId: 'u2' }));
  await rut.assertFails(db.collection('driver_signatures').doc('s1').delete());
});

test('un admin lit le dossier de n importe qui', async () => {
  const db = env.authenticatedContext('a1', { role: 'admin' }).firestore();
  await rut.assertSucceeds(db.collection('driver_program').doc('u2').get());
});

test('un livreur lit la configuration du programme mais ne l ecrit pas', async () => {
  const db = env.authenticatedContext('u1').firestore();
  await rut.assertSucceeds(db.collection('driver_program_settings').doc('config').get());
  await rut.assertFails(db.collection('driver_program_settings').doc('config').set({ theoryPassScore: 1 }));
});
```

- [ ] **Step 3: Lancer les tests et vérifier qu'ils échouent**

Émulateur démarré dans un autre terminal, puis :

```bash
npm test
```

Attendu : ÉCHEC — les règles provisoires refusent tout, donc les tests `assertSucceeds` échouent.

- [ ] **Step 4: Écrire les règles**

Remplacer le contenu de `Order Tracking Firebase Function/firestore.rules` :

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function estConnecte() {
      return request.auth != null;
    }
    function estAdmin() {
      return estConnecte() && request.auth.token.role == 'admin';
    }
    function estMoi(uid) {
      return estConnecte() && request.auth.uid == uid;
    }

    // Le dossier : lecture par son titulaire ou un admin.
    // AUCUNE ecriture directe : tout passe par une Cloud Function.
    match /driver_program/{uid} {
      allow read: if estMoi(uid) || estAdmin();
      allow write: if false;
    }

    match /driver_program_history/{id} {
      allow read: if estAdmin() || (estConnecte() && resource.data.driverId == request.auth.uid);
      allow write: if false;
    }

    match /driver_documents/{id} {
      allow read: if estAdmin() || (estConnecte() && resource.data.driverId == request.auth.uid);
      allow write: if false;
    }

    match /driver_training/{uid} {
      allow read: if estMoi(uid) || estAdmin();
      allow write: if false;
    }

    match /driver_training_modules/{id} {
      allow read: if estConnecte() && resource.data.published == true;
      allow write: if false;
    }

    // La banque de questions porte le corrige : illisible par tous,
    // y compris l'administration. Seul le SDK admin y accede.
    match /driver_training_questions/{id} {
      allow read, write: if false;
    }

    match /driver_theory_attempts/{id} {
      allow read: if estAdmin();
      allow write: if false;
    }

    match /driver_signatures/{id} {
      allow read: if estAdmin() || (estConnecte() && resource.data.driverId == request.auth.uid);
      allow create, update, delete: if false;
    }

    match /driver_agreements/{id} {
      allow read: if estConnecte();
      allow write: if false;
    }

    match /driver_program_settings/{id} {
      allow read: if estConnecte();
      allow write: if false;
    }

    match /driver_program_counters/{id} {
      allow read, write: if false;
    }

    match /driver_audit_log/{id} {
      allow read: if estAdmin();
      allow write: if false;
    }

    // Tout le reste conserve les regles en vigueur, traitees par la spec
    // 2026-08-29-securisation-regles-firestore-design.md. NE PAS MODIFIER ICI.
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

**Le bloc final est la ligne la plus importante de ce fichier.** Il conserve l'ouverture actuelle sur les 33 collections existantes. La retirer ici couperait les quatre applications en production. Sa fermeture appartient au chantier de sécurisation, pas à celui-ci.

Les règles étant évaluées par chemin le plus spécifique, les blocs `driver_*` ci-dessus s'appliquent bien malgré ce joker.

- [ ] **Step 5: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

Attendu : les 9 tests de règles passent.

- [ ] **Step 6: Déployer les règles**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Order Tracking Firebase Function"
firebase deploy --only firestore:rules --project rapyogo-2bccd
```

- [ ] **Step 7: Vérifier immédiatement qu'aucune application n'est cassée**

Ouvrir l'Admin Panel, une liste de commandes, et l'app livreur. Le joker final garantit qu'il n'y a aucun changement pour elles — cette vérification confirme que le déploiement n'a pas eu d'effet de bord.

En cas de problème, retour arrière immédiat : redéployer un `firestore.rules` ne contenant que le bloc joker.

- [ ] **Step 8: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: regles Firestore strictes sur les collections du programme livreur"
```

---

### Task 13: Fonctions d'administration

**Files:**
- Create: `functions/products/driver_program/admin_callables.js`
- Test: `functions/test/driver_program/store.test.js`

**Interfaces:**
- Consumes: `recomputeStatus`, `store.appendAudit`
- Produces: `v1_reviewDocument`, `v1_recordPracticalTest`, `v1_suspendDriver`, `v1_reinstateDriver`, `v1_rejectApplication`, `v1_updateProgramSettings`. Consommées par l'Admin Panel du plan 1C.

- [ ] **Step 1: Écrire les tests qui échouent**

```js
const adm = require('../../products/driver_program/admin_callables');
const ADMIN = { id: 'a1', type: 'admin' };

test('reviewDocument approuve et met a jour le miroir documents_verify', async () => {
  const uid = 'u_review';
  const ref = await db.collection('driver_documents').add({
    driverId: uid, typeId: 'id_proof', status: 'PENDING', version: 1
  });
  await adm.reviewDocument(db, ref.id, 'APPROVED', null, ADMIN);

  const d = await db.collection('driver_documents').doc(ref.id).get();
  assert.strictEqual(d.data().status, 'APPROVED');
  assert.strictEqual(d.data().reviewedBy, 'a1');

  const mirror = await db.collection('documents_verify').doc(uid).get();
  assert.strictEqual(mirror.exists, true);
});

test('reviewDocument exige un motif pour un rejet', async () => {
  const ref = await db.collection('driver_documents').add({
    driverId: 'u_r2', typeId: 'id_proof', status: 'PENDING', version: 1
  });
  await assert.rejects(() => adm.reviewDocument(db, ref.id, 'REJECTED', '', ADMIN), /motif/);
});

test('recordPracticalTest enregistre la note et certifie au seuil', async () => {
  const uid = 'u_prat';
  await db.collection('driver_program_settings').doc('config').set({
    practicalPassScore: 16, theoryPassScore: 24, requiredDocumentTypes: [],
    identityDocumentType: 'id_proof', requiredAgreements: [],
    codeFormat: 'VT-LVR-{seq:6}', referralCodeFormat: 'VT-REF-{seq:6}'
  }, { merge: true });
  await db.collection('driver_training').doc(uid).set({ theory: { bestScore: 27 } }, { merge: true });

  await adm.recordPracticalTest(db, uid, 18, 'Bonne conduite', ADMIN);

  const t = await db.collection('driver_training').doc(uid).get();
  assert.strictEqual(t.data().practical.score, 18);
  assert.ok(t.data().certifiedAt, 'la certification doit etre posee au franchissement du seuil');
});

test('recordPracticalTest ne certifie pas sous le seuil', async () => {
  const uid = 'u_prat2';
  await db.collection('driver_training').doc(uid).set({ theory: { bestScore: 27 } }, { merge: true });
  await adm.recordPracticalTest(db, uid, 12, '', ADMIN);
  const t = await db.collection('driver_training').doc(uid).get();
  assert.strictEqual(t.data().certifiedAt === null || t.data().certifiedAt === undefined, true);
});

test('suspendDriver exige un motif et journalise', async () => {
  const uid = 'u_susp';
  await db.collection('driver_program').doc(uid).set({ driverCode: 'VT-LVR-000030' }, { merge: true });
  await assert.rejects(() => adm.suspendDriver(db, uid, '', ADMIN), /motif/);

  await adm.suspendDriver(db, uid, 'Incident critique', ADMIN);
  const d = await db.collection('driver_program').doc(uid).get();
  assert.strictEqual(d.data().status, 'SUSPENDU');

  const a = await db.collection('driver_audit_log').where('entityId', '==', uid).get();
  assert.ok(a.size >= 1);
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

- [ ] **Step 3: Implémenter**

Créer `functions/products/driver_program/admin_callables.js` :

```js
'use strict';

const admin = require('firebase-admin');
const functions = require('firebase-functions/v1');
const store = require('./store');
const rules = require('./rules');
const callables = require('./callables');

function requireAdmin(context) {
  if (context.auth === null || context.auth === undefined) {
    throw new functions.https.HttpsError('unauthenticated', 'Connexion requise.');
  }
  if (context.auth.token.role !== 'admin') {
    throw new functions.https.HttpsError('permission-denied', 'Reserve a l administration.');
  }
  return context.auth.uid;
}

/**
 * Reconstruit le miroir documents_verify a partir de driver_documents.
 * Sens unique : driver_documents reste l'original, ce miroir n'existe que
 * pour que l'app livreur actuelle continue de fonctionner sans modification.
 */
function rebuildMirror(db, driverId) {
  return db.collection('driver_documents').where('driverId', '==', driverId).get().then((snap) => {
    const documents = snap.docs.map((d) => {
      const x = d.data();
      return {
        documentId: x.typeId,
        frontImage: x.frontURL || '',
        backImage: x.backURL || '',
        status: x.status === 'APPROVED'
      };
    });
    return db.collection('documents_verify').doc(driverId).set({
      id: driverId, documents: documents
    }, { merge: true });
  });
}

function reviewDocument(db, documentId, decision, reason, actor) {
  if (decision === 'REJECTED' && (reason === null || reason === undefined || String(reason).trim() === '')) {
    return Promise.reject(new Error('Un motif est obligatoire pour un rejet.'));
  }
  let driverId = null;
  let previous = null;
  return db.collection('driver_documents').doc(documentId).get().then((snap) => {
    if (snap.exists !== true) {
      throw new Error('Document introuvable.');
    }
    driverId = snap.data().driverId;
    previous = snap.data().status;
    return db.collection('driver_documents').doc(documentId).update({
      status: decision,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedBy: actor.id,
      rejectionReason: decision === 'REJECTED' ? reason : null
    });
  }).then(() => {
    return store.appendAudit(db, {
      actorId: actor.id, actorType: actor.type, action: 'review_document',
      entity: 'driver_documents', entityId: documentId,
      oldValue: previous, newValue: decision, ip: actor.ip || null
    });
  }).then(() => {
    return rebuildMirror(db, driverId);
  }).then(() => {
    return callables.recomputeStatus(db, driverId, actor);
  });
}

function recordPracticalTest(db, uid, score, notes, actor) {
  let settings = null;
  return callables.loadSettings(db).then((s) => {
    settings = s;
    return db.collection('driver_training').doc(uid).get();
  }).then((snap) => {
    const data = snap.exists === true ? snap.data() : {};
    const theory = data.theory || {};
    const theoryOk = (theory.bestScore || 0) >= settings.theoryPassScore;
    const practicalOk = score >= settings.practicalPassScore;
    const patch = {
      practical: { score: score, ratedBy: actor.id, ratedAt: Date.now(), notes: notes || '' }
    };
    if (theoryOk === true && practicalOk === true && (data.certifiedAt === null || data.certifiedAt === undefined)) {
      patch.certifiedAt = Date.now();
      patch.certificateNumber = 'VT-CERT-' + uid.substring(0, 8).toUpperCase();
    }
    return db.collection('driver_training').doc(uid).set(patch, { merge: true });
  }).then(() => {
    return store.appendAudit(db, {
      actorId: actor.id, actorType: actor.type, action: 'record_practical_test',
      entity: 'driver_training', entityId: uid,
      oldValue: null, newValue: score, ip: actor.ip || null
    });
  }).then(() => {
    return callables.recomputeStatus(db, uid, actor);
  });
}

function setAdminStatus(db, uid, adminStatus, reason, actor, action) {
  if (adminStatus !== null && (reason === null || reason === undefined || String(reason).trim() === '')) {
    return Promise.reject(new Error('Un motif est obligatoire.'));
  }
  return db.collection('driver_program').doc(uid).set({ adminStatus: adminStatus }, { merge: true })
    .then(() => {
      return store.appendAudit(db, {
        actorId: actor.id, actorType: actor.type, action: action,
        entity: 'driver_program', entityId: uid,
        oldValue: null, newValue: adminStatus, ip: actor.ip || null
      });
    }).then(() => {
      return callables.recomputeStatus(db, uid, actor);
    });
}

function suspendDriver(db, uid, reason, actor) {
  return setAdminStatus(db, uid, rules.STATUSES.SUSPENDU, reason, actor, 'suspend_driver');
}
function rejectApplication(db, uid, reason, actor) {
  return setAdminStatus(db, uid, rules.STATUSES.REJETE, reason, actor, 'reject_application');
}
function reinstateDriver(db, uid, reason, actor) {
  if (reason === null || reason === undefined || String(reason).trim() === '') {
    return Promise.reject(new Error('Un motif est obligatoire.'));
  }
  return db.collection('driver_program').doc(uid).set({ adminStatus: null }, { merge: true })
    .then(() => {
      return store.appendAudit(db, {
        actorId: actor.id, actorType: actor.type, action: 'reinstate_driver',
        entity: 'driver_program', entityId: uid, oldValue: null, newValue: null, ip: actor.ip || null
      });
    }).then(() => {
      return callables.recomputeStatus(db, uid, actor);
    });
}

function updateProgramSettings(db, patch, actor) {
  return db.collection('driver_program_settings').doc('config').get().then((snap) => {
    const before = snap.exists === true ? snap.data() : {};
    return db.collection('driver_program_settings').doc('config').set(patch, { merge: true })
      .then(() => before);
  }).then((before) => {
    return store.appendAudit(db, {
      actorId: actor.id, actorType: actor.type, action: 'update_program_settings',
      entity: 'driver_program_settings', entityId: 'config',
      oldValue: JSON.stringify(before), newValue: JSON.stringify(patch), ip: actor.ip || null
    });
  });
}

function actorFrom(context) {
  return {
    id: context.auth.uid,
    type: 'admin',
    ip: (context.rawRequest && context.rawRequest.ip) ? context.rawRequest.ip : null
  };
}

const v1_reviewDocument = functions.https.onCall((data, context) => {
  requireAdmin(context);
  return reviewDocument(admin.firestore(), data.documentId, data.decision, data.reason, actorFrom(context))
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
const v1_recordPracticalTest = functions.https.onCall((data, context) => {
  requireAdmin(context);
  return recordPracticalTest(admin.firestore(), data.uid, data.score, data.notes, actorFrom(context))
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
const v1_suspendDriver = functions.https.onCall((data, context) => {
  requireAdmin(context);
  return suspendDriver(admin.firestore(), data.uid, data.reason, actorFrom(context))
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
const v1_reinstateDriver = functions.https.onCall((data, context) => {
  requireAdmin(context);
  return reinstateDriver(admin.firestore(), data.uid, data.reason, actorFrom(context))
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
const v1_rejectApplication = functions.https.onCall((data, context) => {
  requireAdmin(context);
  return rejectApplication(admin.firestore(), data.uid, data.reason, actorFrom(context))
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
const v1_updateProgramSettings = functions.https.onCall((data, context) => {
  requireAdmin(context);
  return updateProgramSettings(admin.firestore(), data.patch || {}, actorFrom(context))
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});

module.exports = {
  requireAdmin: requireAdmin,
  rebuildMirror: rebuildMirror,
  reviewDocument: reviewDocument,
  recordPracticalTest: recordPracticalTest,
  suspendDriver: suspendDriver,
  reinstateDriver: reinstateDriver,
  rejectApplication: rejectApplication,
  updateProgramSettings: updateProgramSettings,
  v1_reviewDocument: v1_reviewDocument,
  v1_recordPracticalTest: v1_recordPracticalTest,
  v1_suspendDriver: v1_suspendDriver,
  v1_reinstateDriver: v1_reinstateDriver,
  v1_rejectApplication: v1_rejectApplication,
  v1_updateProgramSettings: v1_updateProgramSettings
};
```

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: fonctions d'administration du programme livreur"
```

---

### Task 14: Vérification publique du QR code

**Files:**
- Create: `functions/products/driver_program/public.js`
- Test: `functions/test/driver_program/store.test.js`

**Interfaces:**
- Consumes: rien
- Produces: `v1_verifyDriverQr`, fonction HTTP publique. Consommée par la page `/v/{qrToken}` du plan 1B.

- [ ] **Step 1: Écrire les tests qui échouent**

```js
const pub = require('../../products/driver_program/public');

test('publicBadge ne renvoie que les champs non sensibles', async () => {
  const uid = 'u_qr';
  await db.collection('driver_program').doc(uid).set({
    driverCode: 'VT-LVR-000050', qrToken: 'jeton_test_1', level: 2, status: 'ACTIVE',
    profile: {
      firstName: 'Amani', lastName: 'Kabila', photoURL: 'https://s/p.jpg',
      phone: '+243900000002', email: 'a@b.cd', address: 'Goma', primaryZoneId: 'goma'
    }
  });
  await db.collection('driver_training').doc(uid).set({ certifiedAt: 123 }, { merge: true });

  const badge = await pub.publicBadge(db, 'jeton_test_1');
  assert.strictEqual(badge.driverCode, 'VT-LVR-000050');
  assert.strictEqual(badge.firstName, 'Amani');
  assert.strictEqual(badge.lastNameInitial, 'K');
  assert.strictEqual(badge.level, 2);
  assert.strictEqual(badge.actif, true);
  assert.strictEqual(badge.certifie, true);

  assert.strictEqual(badge.lastName, undefined);
  assert.strictEqual(badge.phone, undefined);
  assert.strictEqual(badge.email, undefined);
  assert.strictEqual(badge.address, undefined);
  assert.strictEqual(badge.uid, undefined);
  assert.strictEqual(badge.primaryZoneId, undefined);
});

test('publicBadge rend null pour un jeton inconnu', async () => {
  const badge = await pub.publicBadge(db, 'jeton_inexistant');
  assert.strictEqual(badge, null);
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

- [ ] **Step 3: Implémenter**

Créer `functions/products/driver_program/public.js` :

```js
'use strict';

const admin = require('firebase-admin');
const functions = require('firebase-functions/v1');

/**
 * Badge public d'un livreur, resolu par jeton aleatoire et non par uid.
 *
 * La liste des champs rendus est exhaustive et volontairement courte : un QR
 * code se photographie et se partage, il finit sur des ecrans qu'on ne choisit
 * pas. Ne jamais ajouter ici un champ sans se demander qui pourra le lire.
 */
function publicBadge(db, qrToken) {
  if (typeof qrToken !== 'string' || qrToken.length !== 32) {
    return Promise.resolve(null);
  }
  return db.collection('driver_program').where('qrToken', '==', qrToken).limit(1).get()
    .then((snap) => {
      if (snap.empty === true) {
        return null;
      }
      const doc = snap.docs[0];
      const d = doc.data();
      const profile = d.profile || {};
      const lastName = profile.lastName || '';
      return db.collection('driver_training').doc(doc.id).get().then((t) => {
        const certifie = t.exists === true
          && t.data().certifiedAt !== null && t.data().certifiedAt !== undefined;
        return {
          driverCode: d.driverCode || null,
          firstName: profile.firstName || '',
          lastNameInitial: lastName.length > 0 ? lastName.charAt(0).toUpperCase() : '',
          photoURL: profile.photoURL || null,
          level: d.level || 1,
          actif: d.status === 'ACTIVE',
          certifie: certifie
        };
      });
    });
}

const v1_verifyDriverQr = functions.https.onRequest((req, res) => {
  res.set('Cache-Control', 'public, max-age=60');
  const token = req.query.token;
  return publicBadge(admin.firestore(), token).then((badge) => {
    if (badge === null) {
      res.status(404).json({ trouve: false });
      return null;
    }
    res.status(200).json({ trouve: true, badge: badge });
    return null;
  }).catch((e) => {
    console.error('[DRIVER_PROGRAM] verifyDriverQr : ' + e.message);
    res.status(500).json({ trouve: false });
    return null;
  });
});

module.exports = { publicBadge: publicBadge, v1_verifyDriverQr: v1_verifyDriverQr };
```

Le jeton doit faire exactement 32 caractères — un jeton plus court est refusé sans même interroger Firestore, ce qui coupe court aux tentatives de balayage.

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

Attendu : tous passent, y compris les six assertions vérifiant qu'aucune donnée personnelle ne sort.

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: verification publique du QR code livreur"
```

---

### Task 15: Expiration quotidienne des documents

**Files:**
- Create: `functions/products/driver_program/scheduled.js`
- Test: `functions/test/driver_program/store.test.js`

**Interfaces:**
- Consumes: `callables.recomputeStatus`
- Produces: `expireDriverDocuments`, fonction planifiée

- [ ] **Step 1: Écrire les tests qui échouent**

```js
const sched = require('../../products/driver_program/scheduled');

test('expireDocuments bascule les pieces echues et laisse les autres', async () => {
  const hier = Date.now() - 86400000;
  const demain = Date.now() + 86400000;
  const a = await db.collection('driver_documents').add({
    driverId: 'u_exp', typeId: 'id_proof', status: 'APPROVED', expiresAt: hier, version: 1
  });
  const b = await db.collection('driver_documents').add({
    driverId: 'u_exp', typeId: 'driving_license', status: 'APPROVED', expiresAt: demain, version: 1
  });

  const n = await sched.expireDocuments(db, Date.now());
  assert.strictEqual(n, 1);
  assert.strictEqual((await db.collection('driver_documents').doc(a.id).get()).data().status, 'EXPIRED');
  assert.strictEqual((await db.collection('driver_documents').doc(b.id).get()).data().status, 'APPROVED');
});

test('expireDocuments ignore une piece deja expiree', async () => {
  await db.collection('driver_documents').add({
    driverId: 'u_exp2', typeId: 'id_proof', status: 'EXPIRED', expiresAt: 1, version: 1
  });
  const n = await sched.expireDocuments(db, Date.now());
  assert.strictEqual(n, 0);
});
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```bash
npm test
```

- [ ] **Step 3: Implémenter**

Créer `functions/products/driver_program/scheduled.js` :

```js
'use strict';

const admin = require('firebase-admin');
const functions = require('firebase-functions/v1');
const callables = require('./callables');

/**
 * Bascule en EXPIRED les pieces approuvees dont la date d'echeance est passee,
 * puis recalcule le statut des livreurs concernes.
 *
 * Rappel de conception : cela fait repasser le dossier en PENDING_ACTIVATION
 * mais ne met JAMAIS users.isActive a false. Un livreur avec une piece perimee
 * continue de recevoir des courses jusqu'a une suspension manuelle. C'est
 * assume : couper quelqu'un en plein service est une decision d'exploitation.
 */
function expireDocuments(db, now) {
  return db.collection('driver_documents')
    .where('status', '==', 'APPROVED')
    .where('expiresAt', '<=', now)
    .get()
    .then((snap) => {
      if (snap.empty === true) {
        return 0;
      }
      const updates = snap.docs.map((d) => {
        return db.collection('driver_documents').doc(d.id).update({ status: 'EXPIRED' });
      });
      return Promise.all(updates).then(() => {
        const uids = {};
        snap.docs.forEach((d) => { uids[d.data().driverId] = true; });
        const recomputes = Object.keys(uids).map((uid) => {
          return callables.recomputeStatus(db, uid, { id: 'system', type: 'system' });
        });
        return Promise.all(recomputes).then(() => snap.size);
      });
    });
}

const expireDriverDocuments = functions.pubsub
  .schedule('every day 03:00')
  .timeZone('Africa/Lubumbashi')
  .onRun(() => {
    return expireDocuments(admin.firestore(), Date.now()).then((n) => {
      console.log('[DRIVER_PROGRAM] ' + n + ' piece(s) passee(s) en EXPIRED');
      return null;
    });
  });

module.exports = { expireDocuments: expireDocuments, expireDriverDocuments: expireDriverDocuments };
```

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```bash
npm test
```

Note : ce test nécessite un index composite `driver_documents (status, expiresAt)`. L'émulateur ne l'exige pas ; la production oui. Il est créé en tâche 16.

- [ ] **Step 5: Lint**

```bash
npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: expiration quotidienne des documents livreur"
```

---

### Task 16: Câblage, index, configuration initiale et déploiement

**Files:**
- Modify: `Order Tracking Firebase Function/functions/index.js`
- Create: `Order Tracking Firebase Function/functions/_seed_driver_program.js`

**Interfaces:**
- Consumes: tous les modules des tâches 1 à 15
- Produces: les 16 fonctions déployées sur `rapyogo-2bccd`

- [ ] **Step 1: Câbler dans `index.js`**

Ajouter à la fin de `functions/index.js`, sans rien retirer :

```js
//Programme Partenaires Livreurs
var driverProgram = require('./products/driver_program/callables');
var driverProgramAdmin = require('./products/driver_program/admin_callables');
var driverProgramPublic = require('./products/driver_program/public');
var driverProgramScheduled = require('./products/driver_program/scheduled');

exports.v1_applyAsDriver = driverProgram.v1_applyAsDriver
exports.v1_updateProfile = driverProgram.v1_updateProfile
exports.v1_submitDocument = driverProgram.v1_submitDocument
exports.v1_completeTrainingModule = driverProgram.v1_completeTrainingModule
exports.v1_startTheoryTest = driverProgram.v1_startTheoryTest
exports.v1_submitTheoryTest = driverProgram.v1_submitTheoryTest
exports.v1_signAgreement = driverProgram.v1_signAgreement

exports.v1_reviewDocument = driverProgramAdmin.v1_reviewDocument
exports.v1_recordPracticalTest = driverProgramAdmin.v1_recordPracticalTest
exports.v1_suspendDriver = driverProgramAdmin.v1_suspendDriver
exports.v1_reinstateDriver = driverProgramAdmin.v1_reinstateDriver
exports.v1_rejectApplication = driverProgramAdmin.v1_rejectApplication
exports.v1_updateProgramSettings = driverProgramAdmin.v1_updateProgramSettings

exports.v1_verifyDriverQr = driverProgramPublic.v1_verifyDriverQr
exports.expireDriverDocuments = driverProgramScheduled.expireDriverDocuments
```

- [ ] **Step 2: Créer l'index composite requis**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Order Tracking Firebase Function"
firebase firestore:indexes --project rapyogo-2bccd > /dev/null
```

Puis créer l'index à la main via la console d'erreur : le premier appel réel à `expireDocuments` en production produira un lien direct de création. Alternativement, ajouter à `Firebase Indexing/firestore_indexes.json` :

```json
{
  "collectionGroup": "driver_documents",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "status", "order": "ASCENDING" },
    { "fieldPath": "expiresAt", "order": "ASCENDING" }
  ]
}
```

et déployer :

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Firebase Indexing"
firebase deploy --only firestore:indexes --project rapyogo-2bccd
```

- [ ] **Step 3: Écrire le script de configuration initiale**

Créer `functions/_seed_driver_program.js`. Ce script est exécuté une fois et n'est pas déployé.

```js
'use strict';

const admin = require('firebase-admin');
const sa = require('./serviceAccountKey.json');
if (admin.apps.length === 0) {
  admin.initializeApp({ credential: admin.credential.cert(sa) });
}
const db = admin.firestore();

const CONFIG = {
  codeFormat: 'VT-LVR-{seq:6}',
  referralCodeFormat: 'VT-REF-{seq:6}',
  requiredDocumentTypes: ['id_proof', 'driving_license'],
  identityDocumentType: 'id_proof',
  requiredAgreements: ['partnership'],
  theoryPassScore: 24,
  theoryTotal: 30,
  theoryMaxAttempts: 3,
  practicalPassScore: 16,
  practicalTotal: 20,
  documentExpiryWarningDays: 30,
  // Seuils des §24 et §25 : inscrits, mais INACTIFS a ce stade.
  // Aucune promotion n'est calculee par le chantier 1.
  levelThresholds: {
    level2: { minDeliveries: 100, minScore: 80, minRating: 4.0, minSuccessRate: 0.95 },
    level3: { minDeliveries: 500, minScore: 90, minRating: 4.7, minSuccessRate: 0.97 }
  }
};

const ACCORD = {
  version: 1,
  title: 'Accord de partenariat Viteat',
  body: 'A REMPLACER par le texte juridique valide avant toute ouverture du portail.',
  hash: 'v1-provisoire',
  publishedAt: Date.now()
};

db.collection('driver_program_settings').doc('config').set(CONFIG, { merge: true })
  .then(() => db.collection('driver_agreements').doc('partnership').set(ACCORD, { merge: true }))
  .then(() => db.collection('driver_program_counters').doc('driver_code').get())
  .then((snap) => {
    if (snap.exists === true) {
      console.log('Compteur deja initialise a ' + snap.data().value + ' : inchange.');
      return null;
    }
    return db.collection('driver_program_counters').doc('driver_code').set({ value: 0 });
  })
  .then(() => {
    console.log('Configuration du programme livreur ecrite.');
    process.exit(0);
    return null;
  })
  .catch((e) => {
    console.error('ERREUR : ' + e.message);
    process.exit(1);
  });
```

- [ ] **Step 4: Exécuter la configuration initiale**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Order Tracking Firebase Function/functions"
node _seed_driver_program.js
```

Attendu : « Configuration du programme livreur ecrite. »

- [ ] **Step 5: Vérifier le lint avant déploiement**

```bash
npm run lint
```

Le `predeploy` de `firebase.json` lance cette commande. Si elle échoue, le déploiement est refusé.

- [ ] **Step 6: Déployer en cible**

**Ne jamais utiliser `--only functions` seul** : `helloWorld` et `sendNewOrderNotification`, d'origine inconnue, seraient touchées.

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Order Tracking Firebase Function"
firebase deploy --project rapyogo-2bccd --only \
functions:v1_applyAsDriver,functions:v1_updateProfile,functions:v1_submitDocument,\
functions:v1_completeTrainingModule,functions:v1_startTheoryTest,functions:v1_submitTheoryTest,\
functions:v1_signAgreement,functions:v1_reviewDocument,functions:v1_recordPracticalTest,\
functions:v1_suspendDriver,functions:v1_reinstateDriver,functions:v1_rejectApplication,\
functions:v1_updateProgramSettings,functions:v1_verifyDriverQr,functions:expireDriverDocuments
```

- [ ] **Step 7: Vérifier que les fonctions préexistantes sont intactes**

```bash
firebase functions:list --project rapyogo-2bccd
```

Attendu : `deliveryDispatch`, `deleteUser`, `initiateMobileMoneyPayment`, `checkMobileMoneyStatus`, `flexPayCallback`, `helloWorld` et `sendNewOrderNotification` sont toujours présentes, plus les 15 nouvelles.

- [ ] **Step 8: Vérifier le badge public de bout en bout**

```bash
curl "https://us-central1-rapyogo-2bccd.cloudfunctions.net/v1_verifyDriverQr?token=inexistant"
```

Attendu : `{"trouve":false}` en HTTP 404.

- [ ] **Step 9: Commit**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/customer"
git commit --allow-empty -m "feat: deploiement du noyau backend du programme livreur"
```

---

## Auto-relecture

**Couverture de la spec.** Les §3 (parcours, tâche 5), §4 (profil, tâche 9), §5 (ID, tâches 1-2-6), §6 (QR, tâche 14), §7 (documents, tâches 10 et 13, expiration tâche 15), §8 (formation, tâche 10), §9 (certification, tâche 13), §10 (signature, tâche 11), §11 (activation, tâches 4 et 8), §37 (audit, tâches 7 et 13) et les règles du §4.1 de la spec (tâche 12) sont couverts.

**Non couverts par ce plan, et c'est délibéré** : les écrans du livreur (plan 1B), les vues de l'Admin Panel et les trois rôles RBAC (plan 1C), la reprise des 383 comptes (plan 1C), la redéfinition du catalogue de documents pour la RDC (plan 1C, décision d'exploitation), le rattachement email/téléphone `v1_linkEmailCredential` (plan 1B — c'est une opération purement client, `linkWithCredential` s'appelle depuis le SDK JS et ne justifie pas une Cloud Function).

**Cohérence des types.** `recomputeStatus(db, uid, actor)` prend partout un `actor` de forme `{ id, type }`, éventuellement `{ id, type, ip }` côté admin. `computeActivation(dossier, settings)` et `computeStatus(dossier, activation, settings)` gardent le même ordre d'arguments dans les tâches 4, 5 et 8. `loadDossier` produit exactement les clés que `computeActivation` consomme.

**Deux défauts trouvés à la relecture et corrigés.** `loadDossier` ne chargeait pas les versions en vigueur des accords : la condition `agreement` de `computeActivation` aurait été toujours fausse en production, et **aucun livreur n'aurait jamais pu être activé** — un bug invisible en test, puisque les tests fournissaient l'objet directement. La septième lecture a été ajoutée à la tâche 7, avec le test qui l'aurait attrapé. Une faute de frappe dans la même fonction a par ailleurs été réécrite plutôt que signalée en note.

---

## Suite

**Plan 1B — portail Laravel** : installation de Composer (activer `extension=zip`, php.ini ligne 962), projet Laravel 10, middleware `kreait`, les dix écrans mobile-first.

**Plan 1C — Admin Panel et reprise** : `DriverProgramController`, vues de validation, trois rôles RBAC, script de reprise des 383 comptes en deux populations, redéfinition du catalogue de documents pour la RDC et nettoyage des zones en doublon.
