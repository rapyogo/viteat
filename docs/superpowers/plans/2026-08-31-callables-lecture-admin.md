# Callables de lecture pour l'administration — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sept fonctions callable de lecture, réservées au claim admin, qui alimenteront les vues d'administration du programme Partenaires Livreurs (file des dossiers, fiche, timeline, audit, réglages, modules, questions).

**Architecture:** Nouveau module `read_callables.js` (les 7 `onCall`) + `read_models.js` (fonctions pures testables, aucune importation Firebase, sur le modèle de `rules.js`). Deux retouches d'écriture minimes : champ `searchName` maintenu à l'écriture du profil, champ `driverId` ajouté au journal d'audit. Sept index composites ajoutés puis déployés avant les fonctions (deux index « nus » à un seul champ, envisagés par prudence, ont été rejetés par Firestore comme redondants avec l'indexation automatique — retirés avant déploiement, voir Task 13).

**Tech Stack:** Node 20, firebase-admin 11.11.1, firebase-functions v1, `node --test`, Firestore.

**Spec:** `customer/docs/superpowers/specs/2026-08-31-callables-lecture-admin-design.md` — le plan argumente depuis la spec ; les deux voyagent ensemble.

## Global Constraints

- **Branche** : tout le travail se fait sur `feat/callables-lecture-admin` dans le dépôt `Order Tracking Firebase Function/` (déjà créée). Aucun commit dans `customer/` ni dans `Drive panel/` (ce chantier ne les touche pas).
- **ESLint 2017** (`functions/.eslintrc.json`, ecmaVersion 2017) : ni optional chaining (`?.`), ni nullish coalescing (`??`), ni spread d'objet. `no-await-in-loop`, `eqeqeq`, `no-eq-null`, `promise/always-return`, `promise/catch-or-return` sont des erreurs. Style : chaînes de promesses `.then()` (pas d'`async/await`), commentaires en français **sans accents** (comme le module existant).
- **Tests** : `node --test` **sans argument**, depuis `functions/` (`npm test`). La forme `node --test test/` ne fonctionne pas.
- **Déploiement ciblé**, jamais global : `helloWorld` et `sendNewOrderNotification` ne doivent pas être touchées. Un échec « An unexpected error has occurred » à la découverte est transitoire : relancer suffit.
- **`Firebase Indexing/` n'est pas un dépôt git** : sauvegarder le fichier avant modification.
- **Toutes les dates sortent en ISO 8601** : la sérialisation JSON du runtime onCall convertit les `Timestamp` Firestore automatiquement — ne pas la réimplémenter.
- **Erreurs** : tout refus lève `HttpsError('failed-precondition', message français)` — le code ne discrimine pas les cas, le message est la seule information.

## File Structure

| Fichier | Responsabilité |
|---|---|
| `functions/products/driver_program/read_models.js` | **Créé.** Fonctions pures : normalisation, validation d'entrée, curseurs, projections de file et de fiche. Aucune importation Firebase. |
| `functions/products/driver_program/read_callables.js` | **Créé.** Les 7 `onCall`, `requireAdmin`, lecture Firestore, câblage des pures. |
| `functions/test/driver_program/read_models.test.js` | **Créé.** Tests unitaires des pures. |
| `functions/products/driver_program/store.js` | **Modifié.** `appendAudit` écrit `driverId`. |
| `functions/products/driver_program/callables.js` | **Modifié.** `searchName` posé à `applyAsDriver` et `updateProfile`. |
| `functions/products/driver_program/admin_callables.js` | **Modifié.** `driverId` passé aux 4 sites d'audit portant sur un dossier. |
| `functions/index.js` | **Modifié.** Export des 7 nouvelles fonctions. |
| `Firebase Indexing/firestore_indexes.json` | **Modifié.** 8 index composites ajoutés. |
| `functions/verify_read_callables.js` | **Créé.** Script de vérification post-déploiement (non exécuté par `node --test` : hors de `test/`, nom sans `.test.`). |

---

### Task 1: `read_models.js` — normalisation et routage de recherche

**Files:**
- Create: `functions/products/driver_program/read_models.js`
- Test: `functions/test/driver_program/read_models.test.js`

**Interfaces:**
- Consumes: rien.
- Produces: `normalizeSearchName(firstName, lastName) -> string` (jamais `undefined`), `normalizeCodeTerm(term) -> string`, `routeSearch(term) -> 'code' | 'phone' | 'name'`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `functions/test/driver_program/read_models.test.js` :

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const readModels = require('../../products/driver_program/read_models');

test('normalizeSearchName passe en minuscules et concatene', () => {
  assert.strictEqual(readModels.normalizeSearchName('Rosty', 'Kambale'), 'rosty kambale');
});

test('normalizeSearchName retire les accents', () => {
  assert.strictEqual(readModels.normalizeSearchName('  Hélène  ', 'Nzi-Ébé  '), 'helene nzi-ebe');
});

test('normalizeSearchName ecrase les espaces multiples', () => {
  assert.strictEqual(readModels.normalizeSearchName(' Jean   Pierre ', '  Dufour '), 'jean pierre dufour');
});

test('normalizeSearchName accepte un lastName vide', () => {
  assert.strictEqual(readModels.normalizeSearchName('Rosty', ''), 'rosty');
});

test('normalizeSearchName rend une chaine vide quand tout est vide', () => {
  assert.strictEqual(readModels.normalizeSearchName('', ''), '');
  assert.strictEqual(readModels.normalizeSearchName(null, undefined), '');
});

test('normalizeCodeTerm met en majuscules', () => {
  assert.strictEqual(readModels.normalizeCodeTerm('  vt-lvr-000042  '), 'VT-LVR-000042');
});

test('routeSearch reconnait un code', () => {
  assert.strictEqual(readModels.routeSearch('VT-LVR-000042'), 'code');
  assert.strictEqual(readModels.routeSearch('vt-lvr-00'), 'code');
});

test('routeSearch reconnait un telephone', () => {
  assert.strictEqual(readModels.routeSearch('0998123456'), 'phone');
  assert.strictEqual(readModels.routeSearch('+243 998 123 456'), 'phone');
});

test('routeSearch classe le reste comme un nom', () => {
  assert.strictEqual(readModels.routeSearch('rosty'), 'name');
  assert.strictEqual(readModels.routeSearch('   '), 'name');
});
```

- [ ] **Step 2: Vérifier que le test échoue**

Run: `npm test` (depuis `Order Tracking Firebase Function/functions/`)
Expected: échec — `Cannot find module '../../products/driver_program/read_models'`

- [ ] **Step 3: Implémenter**

Créer `functions/products/driver_program/read_models.js` :

```js
'use strict';

/**
 * Normalise un nom pour la recherche par prefixe : minuscules, accents
 * retires (decomposition NFD puis suppression des marques), espaces ecrases.
 * Rend toujours une chaine, jamais undefined.
 */
function normalizeSearchName(firstName, lastName) {
  const parts = [];
  if (typeof firstName === 'string' && firstName.trim() !== '') {
    parts.push(firstName.trim());
  }
  if (typeof lastName === 'string' && lastName.trim() !== '') {
    parts.push(lastName.trim());
  }
  return parts.join(' ')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Normalise un terme de recherche de code : les codes sont stockes en
 * majuscules, un prefixe de recherche doit donc l'etre aussi.
 */
function normalizeCodeTerm(term) {
  return String(term).trim().toUpperCase();
}

/**
 * Route un terme de recherche vers le champ Firestore interroge. Firestore
 * ne sait pas chercher sur plusieurs champs en OU : la forme du terme
 * choisit le champ. Un terme de telephones exige au moins un chiffre —
 * une chaine d'espaces seuls n'est pas un numero.
 */
function routeSearch(term) {
  const t = String(term).trim();
  if (/^vt-/i.test(t)) {
    return 'code';
  }
  if (/^[0-9+\s]+$/.test(t) && /[0-9]/.test(t)) {
    return 'phone';
  }
  return 'name';
}

module.exports = {
  normalizeSearchName: normalizeSearchName,
  normalizeCodeTerm: normalizeCodeTerm,
  routeSearch: routeSearch
};
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `npm test`
Expected: tous les tests verts (nouveaux + les 82 existants)

- [ ] **Step 5: Commit**

```bash
git add functions/products/driver_program/read_models.js functions/test/driver_program/read_models.test.js
git commit -m "feat(driver-program): normalisation et routage de la recherche (read_models)"
```

---

### Task 2: `read_models.js` — validation d'entrée

**Files:**
- Modify: `functions/products/driver_program/read_models.js`
- Test: `functions/test/driver_program/read_models.test.js`

**Interfaces:**
- Consumes: `STATUSES` de `./rules` (exporté par le module existant).
- Produces: `validatePageInput(data) -> { pageSize, cursor }`, `validateListInput(data) -> { status, zoneId, search, pageSize, cursor }`, `validateUid(uid) -> string`. Tous lèvent une `Error` française sur entrée invalide. `pageSize` défaut 50, plafond 100.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `functions/test/driver_program/read_models.test.js` :

```js
test('validateListInput applique les valeurs par defaut', () => {
  const out = readModels.validateListInput({});
  assert.deepStrictEqual(out, { status: null, zoneId: null, search: null, pageSize: 50, cursor: null });
});

test('validateListInput accepte une combinaison complete', () => {
  const out = readModels.validateListInput({ status: 'DOSSIER_A_VERIFIER', zoneId: 'z1', search: 'rosty', pageSize: 10 });
  assert.strictEqual(out.status, 'DOSSIER_A_VERIFIER');
  assert.strictEqual(out.zoneId, 'z1');
  assert.strictEqual(out.pageSize, 10);
});

test('validateListInput refuse un statut inconnu', () => {
  assert.throws(() => readModels.validateListInput({ status: 'NIMPORTE' }), /Statut inconnu/);
});

test('validateListInput refuse un pageSize hors bornes', () => {
  assert.throws(() => readModels.validateListInput({ pageSize: 0 }), /pageSize/);
  assert.throws(() => readModels.validateListInput({ pageSize: 101 }), /pageSize/);
  assert.throws(() => readModels.validateListInput({ pageSize: 'dix' }), /pageSize/);
});

test('validateListInput refuse une recherche trop longue', () => {
  assert.throws(() => readModels.validateListInput({ search: 'x'.repeat(81) }), /trop longue/);
});

test('validateListInput refuse un curseur malforme', () => {
  assert.throws(() => readModels.validateListInput({ cursor: 'pas-un-objet' }), /Curseur invalide/);
  assert.throws(() => readModels.validateListInput({ cursor: { lastId: '' } }), /Curseur invalide/);
});

test('validatePageInput plafonne pageSize a 100', () => {
  const out = readModels.validatePageInput({ pageSize: 100 });
  assert.strictEqual(out.pageSize, 100);
  assert.throws(() => readModels.validatePageInput({ pageSize: 100.5 }), /pageSize/);
});

test('validateUid exige une chaine non vide', () => {
  assert.strictEqual(readModels.validateUid('abc123'), 'abc123');
  assert.throws(() => readModels.validateUid(''), /uid/);
  assert.throws(() => readModels.validateUid(42), /uid/);
});
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `npm test`
Expected: échec — `readModels.validateListInput is not a function`

- [ ] **Step 3: Implémenter**

Ajouter en tête de `read_models.js` (après `'use strict';`) :

```js
const rules = require('./rules');

const MAX_SEARCH_LENGTH = 80;
const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 100;
```

Ajouter avant `module.exports` :

```js
/**
 * Valide ce qui est commun a toutes les listes paginees : pageSize borne
 * (defaut 50, plafond 100) et forme generale du curseur. Le contenu du
 * curseur est verifie par decodeCursor au moment de l'utiliser.
 */
function validatePageInput(data) {
  const input = data || {};
  let pageSize = DEFAULT_PAGE_SIZE;
  if (input.pageSize !== undefined && input.pageSize !== null) {
    pageSize = Number(input.pageSize);
  }
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > MAX_PAGE_SIZE) {
    throw new Error('pageSize doit etre un entier entre 1 et ' + MAX_PAGE_SIZE + '.');
  }
  let cursor = null;
  if (input.cursor !== undefined && input.cursor !== null) {
    if (typeof input.cursor !== 'object' || typeof input.cursor.lastId !== 'string' || input.cursor.lastId === '') {
      throw new Error('Curseur invalide.');
    }
    cursor = input.cursor;
  }
  return { pageSize: pageSize, cursor: cursor };
}

/**
 * Valide l'entree de v1_listDriverDossiers : statut dans la liste des douze,
 * zone et recherche non vides, recherche bornee, puis la pagination commune.
 */
function validateListInput(data) {
  const input = data || {};
  const page = validatePageInput(input);

  let status = null;
  if (input.status !== undefined && input.status !== null) {
    const allowed = Object.keys(rules.STATUSES).map((k) => rules.STATUSES[k]);
    if (typeof input.status !== 'string' || allowed.indexOf(input.status) === -1) {
      throw new Error('Statut inconnu : ' + input.status);
    }
    status = input.status;
  }

  let zoneId = null;
  if (input.zoneId !== undefined && input.zoneId !== null) {
    if (typeof input.zoneId !== 'string' || input.zoneId.trim() === '') {
      throw new Error('Zone invalide.');
    }
    zoneId = input.zoneId;
  }

  let search = null;
  if (input.search !== undefined && input.search !== null) {
    if (typeof input.search !== 'string' || input.search.trim() === '') {
      throw new Error('Recherche invalide.');
    }
    if (input.search.length > MAX_SEARCH_LENGTH) {
      throw new Error('Recherche trop longue (' + MAX_SEARCH_LENGTH + ' caracteres max).');
    }
    search = input.search;
  }

  return { status: status, zoneId: zoneId, search: search, pageSize: page.pageSize, cursor: page.cursor };
}

/**
 * Exige un identifiant utilisateur : chaine non vide. Toutes les fonctions
 * qui ciblent un dossier passent par ici.
 */
function validateUid(uid) {
  if (typeof uid !== 'string' || uid.trim() === '') {
    throw new Error('uid obligatoire.');
  }
  return uid;
}
```

Et compléter le `module.exports` :

```js
module.exports = {
  normalizeSearchName: normalizeSearchName,
  normalizeCodeTerm: normalizeCodeTerm,
  routeSearch: routeSearch,
  validatePageInput: validatePageInput,
  validateListInput: validateListInput,
  validateUid: validateUid
};
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `npm test`
Expected: tous les tests verts

- [ ] **Step 5: Commit**

```bash
git add functions/products/driver_program/read_models.js functions/test/driver_program/read_models.test.js
git commit -m "feat(driver-program): validation d'entree des listes (read_models)"
```

---

### Task 3: `read_models.js` — curseurs de pagination

**Files:**
- Modify: `functions/products/driver_program/read_models.js`
- Test: `functions/test/driver_program/read_models.test.js`

**Interfaces:**
- Consumes: rien de nouveau.
- Produces: `encodeCursor(timestamp, id, fieldName) -> { [fieldName]: { seconds, nanoseconds }, lastId }`, `decodeCursor(cursor, fieldName) -> { timestamp: { seconds, nanoseconds }, lastId }`. `fieldName` est un nom logique (`appliedAt`, `at`) — jamais un chemin Firestore à points.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `functions/test/driver_program/read_models.test.js` :

```js
test('encodeCursor puis decodeCursor font l aller-retour', () => {
  const encoded = readModels.encodeCursor({ seconds: 1725130000, nanoseconds: 123456789 }, 'doc-42', 'appliedAt');
  assert.deepStrictEqual(encoded, { appliedAt: { seconds: 1725130000, nanoseconds: 123456789 }, lastId: 'doc-42' });
  const decoded = readModels.decodeCursor(encoded, 'appliedAt');
  assert.deepStrictEqual(decoded, { timestamp: { seconds: 1725130000, nanoseconds: 123456789 }, lastId: 'doc-42' });
});

test('decodeCursor refuse un curseur sans horodatage', () => {
  assert.throws(() => readModels.decodeCursor({ lastId: 'doc-42' }, 'appliedAt'), /Curseur invalide/);
});

test('decodeCursor refuse un horodatage non entier', () => {
  const bad = { appliedAt: { seconds: 'maintenant', nanoseconds: 1 }, lastId: 'doc-42' };
  assert.throws(() => readModels.decodeCursor(bad, 'appliedAt'), /Curseur invalide/);
});

test('decodeCursor refuse un lastId vide', () => {
  const bad = { appliedAt: { seconds: 1, nanoseconds: 0 }, lastId: '' };
  assert.throws(() => readModels.decodeCursor(bad, 'appliedAt'), /Curseur invalide/);
});
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `npm test`
Expected: échec — `readModels.encodeCursor is not a function`

- [ ] **Step 3: Implémenter**

Ajouter avant `module.exports` dans `read_models.js` :

```js
/**
 * Empaquette le curseur de la derniere ligne rendue. Le Timestamp Firestore
 * est porte ENTIER (secondes + nanosecondes) : aucune conversion en millis,
 * donc aucune perte de precision ni doublon en frontiere de page.
 */
function encodeCursor(timestamp, id, fieldName) {
  const out = { lastId: id };
  out[fieldName] = { seconds: timestamp.seconds, nanoseconds: timestamp.nanoseconds };
  return out;
}

/**
 * Controle la forme d'un curseur recu et en extrait l'horodatage. Le client
 * renvoie le curseur tel quel : on le verifie avant de le donner a startAfter.
 */
function decodeCursor(cursor, fieldName) {
  if (cursor === null || cursor === undefined || typeof cursor !== 'object') {
    throw new Error('Curseur invalide.');
  }
  const stamp = cursor[fieldName];
  const id = cursor.lastId;
  if (stamp === null || stamp === undefined || typeof stamp !== 'object'
      || !Number.isInteger(stamp.seconds) || !Number.isInteger(stamp.nanoseconds)) {
    throw new Error('Curseur invalide.');
  }
  if (typeof id !== 'string' || id === '') {
    throw new Error('Curseur invalide.');
  }
  return { timestamp: stamp, lastId: id };
}
```

Et compléter le `module.exports` :

```js
  encodeCursor: encodeCursor,
  decodeCursor: decodeCursor
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `npm test`
Expected: tous les tests verts

- [ ] **Step 5: Commit**

```bash
git add functions/products/driver_program/read_models.js functions/test/driver_program/read_models.test.js
git commit -m "feat(driver-program): curseurs de pagination (read_models)"
```

---

### Task 4: `read_models.js` — projection de ligne de file

**Files:**
- Modify: `functions/products/driver_program/read_models.js`
- Test: `functions/test/driver_program/read_models.test.js`

**Interfaces:**
- Consumes: rien de nouveau.
- Produces: `buildDossierRow(doc, zonesById) -> objet` — `doc` est un `DocumentSnapshot`-like : `doc.id` et `doc.data()`. `zonesById` est un objet `{ zoneId: nom }`.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `functions/test/driver_program/read_models.test.js` :

```js
function fakeDoc(id, data) {
  return { id: id, data: () => data };
}

test('buildDossierRow projette les champs de la ligne', () => {
  const doc = fakeDoc('uid-1', {
    driverCode: 'VT-LVR-000042',
    status: 'DOSSIER_A_VERIFIER',
    profile: { firstName: 'Rosty', lastName: 'Kambale', phone: '+243998000000', primaryZoneId: 'zone-goma' },
    dates: { appliedAt: { seconds: 1, nanoseconds: 0 }, activatedAt: null }
  });
  const row = readModels.buildDossierRow(doc, { 'zone-goma': 'Goma Centre' });
  assert.strictEqual(row.uid, 'uid-1');
  assert.strictEqual(row.driverCode, 'VT-LVR-000042');
  assert.strictEqual(row.firstName, 'Rosty');
  assert.strictEqual(row.lastName, 'Kambale');
  assert.strictEqual(row.phone, '+243998000000');
  assert.strictEqual(row.status, 'DOSSIER_A_VERIFIER');
  assert.strictEqual(row.primaryZoneId, 'zone-goma');
  assert.strictEqual(row.zoneName, 'Goma Centre');
  assert.deepStrictEqual(row.appliedAt, { seconds: 1, nanoseconds: 0 });
  assert.strictEqual(row.activatedAt, null);
});

test('buildDossierRow rend zoneName null pour une zone inconnue', () => {
  const doc = fakeDoc('uid-2', {
    profile: { primaryZoneId: 'zone-inconnue' },
    dates: {}
  });
  const row = readModels.buildDossierRow(doc, { 'zone-goma': 'Goma Centre' });
  assert.strictEqual(row.zoneName, null);
});

test('buildDossierRow survit a un profil absent', () => {
  const row = readModels.buildDossierRow(fakeDoc('uid-3', {}), {});
  assert.strictEqual(row.firstName, null);
  assert.strictEqual(row.status, null);
  assert.strictEqual(row.zoneName, null);
});

test('buildDossierRow ne laisse passer que les champs de la ligne', () => {
  const doc = fakeDoc('uid-4', { qrToken: 'secret', profile: { address: 'rue 1' } });
  const row = readModels.buildDossierRow(doc, {});
  assert.deepStrictEqual(Object.keys(row).sort(), [
    'activatedAt', 'appliedAt', 'driverCode', 'firstName', 'lastName',
    'phone', 'primaryZoneId', 'status', 'uid', 'zoneName'
  ]);
});
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `npm test`
Expected: échec — `readModels.buildDossierRow is not a function`

- [ ] **Step 3: Implémenter**

Ajouter avant `module.exports` dans `read_models.js` :

```js
/**
 * Projette une ligne de la file des dossiers. Volontairement legere :
 * ni adresse, ni email, ni qrToken, ni detail bancaire ne sortent d'ici —
 * la fiche (buildDossierDetail) porte le detail. Les horodatages partent
 * tels quels : la serialisation du runtime onCall les rend en ISO 8601.
 */
function buildDossierRow(doc, zonesById) {
  const data = doc.data();
  const profile = data.profile || {};
  const dates = data.dates || {};
  const primaryZoneId = profile.primaryZoneId || null;
  let zoneName = null;
  if (primaryZoneId !== null && zonesById[primaryZoneId] !== undefined) {
    zoneName = zonesById[primaryZoneId];
  }
  return {
    uid: doc.id,
    driverCode: data.driverCode || null,
    firstName: profile.firstName || null,
    lastName: profile.lastName || null,
    phone: profile.phone || null,
    status: data.status || null,
    primaryZoneId: primaryZoneId,
    zoneName: zoneName,
    appliedAt: dates.appliedAt || null,
    activatedAt: dates.activatedAt || null
  };
}
```

Et compléter le `module.exports` :

```js
  buildDossierRow: buildDossierRow
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `npm test`
Expected: tous les tests verts

- [ ] **Step 5: Commit**

```bash
git add functions/products/driver_program/read_models.js functions/test/driver_program/read_models.test.js
git commit -m "feat(driver-program): projection de ligne de file (read_models)"
```

---

### Task 5: `read_models.js` — projection de fiche et composition du searchName

**Files:**
- Modify: `functions/products/driver_program/read_models.js`
- Test: `functions/test/driver_program/read_models.test.js`

**Interfaces:**
- Consumes: `loadDossier` (via sa forme de retour : `{ program, profile, adminStatus, user, documents, training, signatures, requiredModuleIds, agreementVersions }`) — voir `store.js`.
- Produces: `buildDossierDetail(dossier, catalogById, requiredDocumentTypes) -> objet` (contrat exact au §4.2 de la spec), `composeSearchName(patch, existingProfile) -> string`.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `functions/test/driver_program/read_models.test.js` :

```js
function makeDossier() {
  return {
    program: {
      driverCode: 'VT-LVR-000042', referralCode: 'VT-REF-000042', level: 1,
      status: 'DOSSIER_A_VERIFIER', adminStatus: null,
      dates: { appliedAt: { seconds: 1, nanoseconds: 0 } },
      activation: { identity: false, documents: false, training: true, theoryTest: false,
        practicalTest: false, certification: false, agreement: false,
        payoutAccount: false, profileComplete: true }
    },
    profile: { firstName: 'Rosty', lastName: 'Kambale', phone: '+243998000000' },
    adminStatus: null,
    user: { zoneId: 'zone-goma', fcmToken: 'un-jeton', userBankDetails: { bank: 'Equity' } },
    documents: [
      { id: 'd1', typeId: 'wNsq0pdDbbmjXkHKwtNv', status: 'PENDING', version: 2,
        submittedAt: { toMillis: () => 1000 } },
      { id: 'd2', typeId: 'tsTemfO52potrI6knLeO', status: 'APPROVED', version: 1,
        submittedAt: { toMillis: () => 2000 } }
    ],
    training: { modules: [], theory: { bestScore: 24 }, practical: null, certifiedAt: null },
    signatures: [{ documentType: 'partenariat', documentVersion: 1, fullNameTyped: 'Rosty Kambale',
      signedAt: { seconds: 1, nanoseconds: 0 }, ip: '1.2.3.4', userAgent: 'test' }],
    requiredModuleIds: ['m1'],
    agreementVersions: { partenariat: 1 }
  };
}

test('buildDossierDetail projette la fiche complete', () => {
  const detail = readModels.buildDossierDetail(makeDossier(),
    { 'wNsq0pdDbbmjXkHKwtNv': { title: 'ID Proof' } }, ['wNsq0pdDbbmjXkHKwtNv']);
  assert.strictEqual(detail.program.driverCode, 'VT-LVR-000042');
  assert.strictEqual(detail.program.status, 'DOSSIER_A_VERIFIER');
  assert.strictEqual(detail.user.payoutReady, true);
  assert.strictEqual(detail.user.hasFcmToken, true);
  assert.strictEqual(detail.user.zoneId, 'zone-goma');
  assert.deepStrictEqual(detail.requiredDocumentTypes, ['wNsq0pdDbbmjXkHKwtNv']);
  assert.strictEqual(detail.activation.profileComplete, true);
  // Tri par depot le plus recent : d2 (submittedAt 2000, hors catalogue) en
  // position 0, d1 (submittedAt 1000, catalogue) en position 1 — voir le test
  // dedie au tri ci-dessous pour la preuve de l'ordre.
  assert.strictEqual(detail.documents[0].title, null);
  assert.strictEqual(detail.documents[1].title, 'ID Proof');
});

test('buildDossierDetail trie les pieces par depot le plus recent', () => {
  const detail = readModels.buildDossierDetail(makeDossier(), {}, []);
  assert.strictEqual(detail.documents[0].id, 'd2');
  assert.strictEqual(detail.documents[1].id, 'd1');
});

test('buildDossierDetail rend payoutReady false sans compte bancaire', () => {
  const dossier = makeDossier();
  dossier.user.userBankDetails = {};
  const detail = readModels.buildDossierDetail(dossier, {}, []);
  assert.strictEqual(detail.user.payoutReady, false);
});

test('buildDossierDetail rend hasFcmToken false sans jeton', () => {
  const dossier = makeDossier();
  dossier.user.fcmToken = null;
  const detail = readModels.buildDossierDetail(dossier, {}, []);
  assert.strictEqual(detail.user.hasFcmToken, false);
});

test('buildDossierDetail rend hasFcmToken false pour une chaine vide', () => {
  const dossier = makeDossier();
  dossier.user.fcmToken = '';
  const detail = readModels.buildDossierDetail(dossier, {}, []);
  assert.strictEqual(detail.user.hasFcmToken, false);
});

test('composeSearchName combine le patch avec le profil existant', () => {
  assert.strictEqual(
    readModels.composeSearchName({ lastName: 'Kambale' }, { firstName: 'Rosty' }),
    'rosty kambale');
  assert.strictEqual(
    readModels.composeSearchName({ firstName: 'Jean', lastName: 'Dufour' }, {}),
    'jean dufour');
});
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `npm test`
Expected: échec — `readModels.buildDossierDetail is not a function`

- [ ] **Step 3: Implémenter**

Ajouter avant `module.exports` dans `read_models.js` :

```js
/**
 * Reconstruit le searchName d'un profil a partir d'un patch partiel : un
 * patch ne portant que lastName doit se composer avec le firstName existant.
 */
function composeSearchName(patch, existingProfile) {
  const firstName = patch.firstName !== undefined ? patch.firstName : (existingProfile.firstName || '');
  const lastName = patch.lastName !== undefined ? patch.lastName : (existingProfile.lastName || '');
  return normalizeSearchName(firstName, lastName);
}

/**
 * Lit un horodatage sous les trois formes possibles en test et en production :
 * Timestamp Firestore (toMillis), Date, nombre. Tout le reste vaut 0 — un
 * document sans date de depot se retrouve en fin de liste, jamais exclu.
 */
function stampValue(value) {
  if (value === null || value === undefined) {
    return 0;
  }
  if (typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === 'number') {
    return value;
  }
  return 0;
}

/**
 * Projette la fiche complete d'un dossier (§4.2 de la spec). Rend les
 * valeurs MEMORISEES de status et activation — aucun recalcul : la fiche
 * est un outil de verification, pas un moteur. Les presences sortent,
 * jamais les valeurs : payoutReady et hasFcmToken, pas le detail bancaire
 * ni le jeton FCM.
 */
function buildDossierDetail(dossier, catalogById, requiredDocumentTypes) {
  const profile = dossier.profile || {};
  const user = dossier.user || {};
  const training = dossier.training || {};
  const bank = user.userBankDetails;
  const payoutReady = bank !== null && bank !== undefined
    && typeof bank === 'object' && Object.keys(bank).length > 0;

  const documents = (dossier.documents || [])
    .slice()
    .sort((a, b) => stampValue(b.submittedAt) - stampValue(a.submittedAt))
    .map((d) => {
      const catalog = catalogById[d.typeId];
      return {
        id: d.id,
        typeId: d.typeId,
        title: catalog !== undefined ? (catalog.title || null) : null,
        status: d.status,
        rejectionReason: d.rejectionReason || null,
        frontURL: d.frontURL || null,
        backURL: d.backURL || null,
        version: d.version || null,
        submittedAt: d.submittedAt || null,
        expiresAt: d.expiresAt || null,
        reviewedAt: d.reviewedAt || null,
        reviewedBy: d.reviewedBy || null
      };
    });

  return {
    program: {
      driverCode: dossier.program.driverCode || null,
      referralCode: dossier.program.referralCode || null,
      level: dossier.program.level || null,
      status: dossier.program.status || null,
      adminStatus: dossier.program.adminStatus || null,
      dates: dossier.program.dates || {}
    },
    profile: {
      firstName: profile.firstName || null,
      lastName: profile.lastName || null,
      photoURL: profile.photoURL || null,
      phone: profile.phone || null,
      email: profile.email || null,
      address: profile.address || null,
      primaryZoneId: profile.primaryZoneId || null,
      secondaryZoneIds: profile.secondaryZoneIds || [],
      vehicleType: profile.vehicleType || null
    },
    user: {
      zoneId: user.zoneId || null,
      payoutReady: payoutReady,
      hasFcmToken: typeof user.fcmToken === 'string' && user.fcmToken !== ''
    },
    documents: documents,
    training: {
      modules: training.modules || [],
      theory: training.theory || null,
      practical: training.practical || null,
      certifiedAt: training.certifiedAt || null,
      certificateNumber: training.certificateNumber || null
    },
    signatures: (dossier.signatures || []).map((s) => ({
      documentType: s.documentType,
      documentVersion: s.documentVersion,
      fullNameTyped: s.fullNameTyped,
      signedAt: s.signedAt || null,
      ip: s.ip || null,
      userAgent: s.userAgent || null
    })),
    activation: dossier.program.activation || {},
    requiredDocumentTypes: requiredDocumentTypes,
    requiredModuleIds: dossier.requiredModuleIds || [],
    agreementVersions: dossier.agreementVersions || {}
  };
}
```

Et compléter le `module.exports` :

```js
  composeSearchName: composeSearchName,
  buildDossierDetail: buildDossierDetail
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `npm test`
Expected: tous les tests verts

- [ ] **Step 5: Commit**

```bash
git add functions/products/driver_program/read_models.js functions/test/driver_program/read_models.test.js
git commit -m "feat(driver-program): projection de fiche et searchName compose (read_models)"
```

---

### Task 6: `store.js` — `driverId` dans le journal d'audit

**Files:**
- Modify: `functions/products/driver_program/store.js:88-92` (fonction `appendAudit`)

**Interfaces:**
- Consumes: les appels existants d'`appendAudit(db, entry)` — inchangés (le champ devient optionnel).
- Produces: toute ligne de `driver_audit_log` porte `driverId` (null pour le global).

Pas de test unitaire : la retouche est une ligne de glue Firestore. La vérification est la non-régression (`npm test` complet) plus le lint.

- [ ] **Step 1: Modifier `appendAudit`**

Dans `functions/products/driver_program/store.js`, remplacer :

```js
function appendAudit(db, entry) {
  return db.collection('driver_audit_log').add(
    Object.assign({}, entry, { at: admin.firestore.FieldValue.serverTimestamp() })
  );
}
```

par :

```js
function appendAudit(db, entry) {
  // driverId est optionnel : les actions globales (reglages du programme)
  // n'en ont pas. Sans ce champ, filtrer le journal par dossier exigerait
  // une jointure artificielle par entity/entityId illisible.
  return db.collection('driver_audit_log').add(
    Object.assign({}, entry, { driverId: entry.driverId || null, at: admin.firestore.FieldValue.serverTimestamp() })
  );
}
```

- [ ] **Step 2: Vérifier la non-régression et le lint**

Run: `npm test` puis `npm run lint`
Expected: les 82+ tests existants passent, lint sans erreur

- [ ] **Step 3: Commit**

```bash
git add functions/products/driver_program/store.js
git commit -m "feat(driver-program): driverId dans le journal d'audit"
```

---

### Task 7: `callables.js` — `searchName` maintenu à l'écriture

**Files:**
- Modify: `functions/products/driver_program/callables.js:141-159` (`writeApplicationInTransaction`), `functions/products/driver_program/callables.js:204-216` (`updateProfile`), et le haut du fichier (require)

**Interfaces:**
- Consumes: `normalizeSearchName`, `composeSearchName` de `./read_models` (Tasks 1 et 5).
- Produces: tout dossier créé ou profil mis à jour porte `searchName` à jour.

La logique testable (`composeSearchName`, `normalizeSearchName`) est déjà couverte ; ici on la câble. Vérification : `npm test` + lint.

- [ ] **Step 1: Ajouter le require**

Dans `functions/products/driver_program/callables.js`, sous `const store = require('./store');` (ligne 7), ajouter :

```js
const readModels = require('./read_models');
```

- [ ] **Step 2: Poser `searchName` à la création du dossier**

Dans `writeApplicationInTransaction`, le `tx.set(ref, {...})` porte déjà `profile: pickProfile(profileInput)`. Ajouter une ligne dans l'objet passé à `tx.set`, après `qrToken: crypto.randomBytes(16).toString('hex'),` :

```js
      searchName: readModels.normalizeSearchName(profileInput.firstName, profileInput.lastName),
```

- [ ] **Step 3: Maintenir `searchName` à la mise à jour du profil**

Remplacer la fonction `updateProfile` (actuellement une lecture → un patch → une écriture) par cette version, qui relit le profil existant **uniquement** quand le patch touche un nom. `resolveSearchNamePatch` est extraite en fonction nommée pour éviter un `.then()` imbriqué dans le `.then()` appelant (`promise/no-nesting`), même motif que `writeApplicationInTransaction` plus haut dans ce fichier :

```js
/**
 * Recalcule searchName quand le patch touche firstName ou lastName, en
 * composant avec le profil existant (un patch partiel — lastName seul — ne
 * doit pas effacer le firstName du terme de recherche). Rend null si le nom
 * n'est pas touche.
 */
function resolveSearchNamePatch(db, uid, clean, touchesName) {
  if (touchesName !== true) {
    return Promise.resolve(null);
  }
  return db.collection('driver_program').doc(uid).get().then((snap) => {
    const existing = (snap.exists === true && snap.data().profile) ? snap.data().profile : {};
    return readModels.composeSearchName(clean, existing);
  });
}

/**
 * Met a jour le profil d'un livreur deja candidat. Champs hors liste blanche
 * silencieusement ignores (pas d'erreur : le portail peut envoyer un objet
 * plus large sans que ca ne devienne une faille d'ecriture).
 *
 * Quand le patch touche firstName ou lastName, searchName est recalcule et
 * ajoute au patch : sans lui, la recherche par nom de la file deviendrait
 * muette des qu'un candidat corrige son nom.
 */
function updateProfile(db, uid, profileInput) {
  const clean = pickProfile(profileInput);
  const patch = {};
  Object.keys(clean).forEach((k) => {
    patch['profile.' + k] = clean[k];
  });
  if (Object.keys(patch).length === 0) {
    return recomputeStatus(db, uid, { id: uid, type: 'driver' });
  }
  const touchesName = clean.firstName !== undefined || clean.lastName !== undefined;
  return resolveSearchNamePatch(db, uid, clean, touchesName).then((searchName) => {
    if (searchName !== null) {
      patch.searchName = searchName;
    }
    return db.collection('driver_program').doc(uid).update(patch);
  }).then(() => {
    return recomputeStatus(db, uid, { id: uid, type: 'driver' });
  });
}
```

- [ ] **Step 4: Vérifier la non-régression et le lint**

Run: `npm test` puis `npm run lint`
Expected: tous les tests passent, lint sans erreur

- [ ] **Step 5: Commit**

```bash
git add functions/products/driver_program/callables.js
git commit -m "feat(driver-program): searchName maintenu a la creation et a l'edition du profil"
```

---

### Task 8: `admin_callables.js` — `driverId` sur les écritures d'audit

**Files:**
- Modify: `functions/products/driver_program/admin_callables.js` — les 4 appels `store.appendAudit` portant sur un dossier (lignes ~129, ~174, ~200, ~233). `updateProgramSettings` (~263) reste inchangé.

**Interfaces:**
- Consumes: `appendAudit` acceptant `driverId` (Task 6).
- Produces: chaque ligne d'audit d'action sur un dossier porte son `driverId`.

- [ ] **Step 1: Ajouter `driverId` aux quatre sites**

1. Dans `reviewDocument` (après la lecture du document, `driverId` est déjà disponible — le paramètre de l'appel `store.appendAudit` est un objet littéral), ajouter `driverId: driverId` dans l'objet passé à `store.appendAudit` :
```js
      actorId: actor.id, actorType: actor.type, action: 'review_document',
      entity: 'driver_documents', entityId: documentId,
      oldValue: previous, newValue: decision, ip: actor.ip || null,
      driverId: driverId
```
2. Dans `recordPracticalTest` : ajouter `driverId: uid` à l'objet de `store.appendAudit`.
3. Dans `setAdminStatus` (suspendre / réintégrer / rejeter) : ajouter `driverId: uid` à l'objet de `store.appendAudit`.
4. Dans `reinstateDriver` : ajouter `driverId: uid` à l'objet de `store.appendAudit`.

Ne pas toucher à `updateProgramSettings` : c'est une action globale, `driverId` reste `null` (le défaut posé par `appendAudit`).

- [ ] **Step 2: Vérifier la non-régression et le lint**

Run: `npm test` puis `npm run lint`
Expected: tous les tests passent, lint sans erreur

- [ ] **Step 3: Commit**

```bash
git add functions/products/driver_program/admin_callables.js
git commit -m "feat(driver-program): driverId sur les actions d'audit par dossier"
```

---

### Task 9: `read_callables.js` — socle et trois fonctions simples

**Files:**
- Create: `functions/products/driver_program/read_callables.js`
- Modify: `functions/index.js:49` (ajout des exports)

**Interfaces:**
- Consumes: `requireAdmin` de `./admin_callables`, `loadSettings` de `./callables`, `validatePageInput` de `./read_models`.
- Produces: `v1_getProgramSettings`, `v1_listTrainingModules`, `v1_listTrainingQuestions`, et les helpers internes `applyCursor`, `nextCursorFrom` que les Tasks 10-12 réutiliseront.

- [ ] **Step 1: Créer `read_callables.js`**

```js
'use strict';

const admin = require('firebase-admin');
const functions = require('firebase-functions/v1');
const store = require('./store');
const callables = require('./callables');
const readModels = require('./read_models');
const adminCallables = require('./admin_callables');

/**
 * Applique le curseur a une requete : le decode, reconstruit le Timestamp
 * Firestore exact (secondes + nanosecondes) et repart apres la derniere
 * ligne rendue. Sans curseur, la requete repart du debut.
 */
function applyCursor(query, cursor, fieldName) {
  if (cursor === null) {
    return query;
  }
  const decoded = readModels.decodeCursor(cursor, fieldName);
  const stamp = new admin.firestore.Timestamp(decoded.timestamp.seconds, decoded.timestamp.nanoseconds);
  return query.startAfter(stamp, decoded.lastId);
}

/**
 * Rendu le curseur de la page suivante : null quand la page rendue compte
 * moins de pageSize elements (il n'y a rien apres). extractStamp lit
 * l'horodatage dans un docData ; fieldName est le nom logique du champ
 * (appliedAt, at) — jamais un chemin Firestore a points.
 */
function nextCursorFrom(snapshot, pageSize, extractStamp, fieldName) {
  if (snapshot.docs.length < pageSize) {
    return null;
  }
  const last = snapshot.docs[snapshot.docs.length - 1];
  return readModels.encodeCursor(extractStamp(last.data()), last.id, fieldName);
}

/**
 * Rend la configuration complete du programme. La config absente est une
 * erreur explicite (meme garde que loadSettings cote ecriture) : une fiche
 * ou une file qui s'afficherait avec des seuils vides mentirait.
 */
const v1_getProgramSettings = functions.https.onCall((data, context) => {
  adminCallables.requireAdmin(context);
  return callables.loadSettings(admin.firestore())
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});

/**
 * Rend TOUS les modules — publies et brouillons, l'editeur a besoin des
 * deux. Tri par __name__ uniquement : ordonner sur `order` exclurait
 * silencieusement tout module qui ne le porte pas (spec §4.6).
 */
const v1_listTrainingModules = functions.https.onCall((data, context) => {
  adminCallables.requireAdmin(context);
  return admin.firestore().collection('driver_training_modules')
    .orderBy(admin.firestore.FieldPath.documentId(), 'asc')
    .get().then((snap) => {
      return { items: snap.docs.map((d) => Object.assign({ id: d.id }, d.data())) };
    })
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});

/**
 * Rend TOUTES les questions AVEC leur correctIndex. C'est le seul chemin
 * par lequel le corrige sort du backend, et il est reserve au claim admin
 * (spec §4.7) : sans lui, aucun editeur de banque de questions.
 */
const v1_listTrainingQuestions = functions.https.onCall((data, context) => {
  adminCallables.requireAdmin(context);
  return admin.firestore().collection('driver_training_questions')
    .orderBy(admin.firestore.FieldPath.documentId(), 'asc')
    .get().then((snap) => {
      return { items: snap.docs.map((d) => Object.assign({ id: d.id }, d.data())) };
    })
    .catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});

module.exports = {
  applyCursor: applyCursor,
  nextCursorFrom: nextCursorFrom,
  v1_getProgramSettings: v1_getProgramSettings,
  v1_listTrainingModules: v1_listTrainingModules,
  v1_listTrainingQuestions: v1_listTrainingQuestions
};
```

- [ ] **Step 2: Exporter dans `index.js`**

À la fin de `functions/index.js`, après la ligne `exports.v1_updateProgramSettings = ...` :

```js
var driverProgramRead = require('./products/driver_program/read_callables');

exports.v1_getProgramSettings = driverProgramRead.v1_getProgramSettings
exports.v1_listTrainingModules = driverProgramRead.v1_listTrainingModules
exports.v1_listTrainingQuestions = driverProgramRead.v1_listTrainingQuestions
```

- [ ] **Step 3: Vérifier le lint et la non-régression**

Run: `npm run lint` puis `npm test`
Expected: lint sans erreur, tous les tests passent

- [ ] **Step 4: Commit**

```bash
git add functions/products/driver_program/read_callables.js functions/index.js
git commit -m "feat(driver-program): callables de lecture — reglages, modules, questions"
```

---

### Task 10: `read_callables.js` — `v1_getDriverDossier`

**Files:**
- Modify: `functions/products/driver_program/read_callables.js`, `functions/index.js`

**Interfaces:**
- Consumes: `store.loadDossier`, `callables.loadSettings`, `readModels.validateUid`, `readModels.buildDossierDetail`.
- Produces: `v1_getDriverDossier`.

- [ ] **Step 1: Ajouter la fonction**

Dans `read_callables.js`, avant `module.exports` :

```js
/**
 * Rend la fiche complete d'un dossier (§4.2 de la spec). Reutilise
 * loadDossier (7 lectures en parallele) et ajoute le catalogue `documents`
 * pour resoudre typeId -> titre, plus les types requis depuis la config.
 */
const v1_getDriverDossier = functions.https.onCall((data, context) => {
  adminCallables.requireAdmin(context);
  const uid = readModels.validateUid((data || {}).uid);
  return Promise.all([
    store.loadDossier(admin.firestore(), uid),
    admin.firestore().collection('documents').get(),
    callables.loadSettings(admin.firestore())
  ]).then((results) => {
    const catalogById = {};
    results[1].docs.forEach((d) => {
      catalogById[d.id] = d.data();
    });
    return readModels.buildDossierDetail(results[0], catalogById, results[2].requiredDocumentTypes || []);
  }).catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
```

Ajouter au `module.exports` :

```js
  v1_getDriverDossier: v1_getDriverDossier
```

- [ ] **Step 2: Exporter dans `index.js`**

```js
exports.v1_getDriverDossier = driverProgramRead.v1_getDriverDossier
```

- [ ] **Step 3: Vérifier le lint et la non-régression**

Run: `npm run lint` puis `npm test`
Expected: lint sans erreur, tous les tests passent

- [ ] **Step 4: Commit**

```bash
git add functions/products/driver_program/read_callables.js functions/index.js
git commit -m "feat(driver-program): callable de lecture — fiche dossier"
```

---

### Task 11: `read_callables.js` — timeline et journal d'audit

**Files:**
- Modify: `functions/products/driver_program/read_callables.js`, `functions/index.js`

**Interfaces:**
- Consumes: `applyCursor`, `nextCursorFrom` (Task 9), `validatePageInput`, `validateUid`.
- Produces: `v1_listDriverHistory`, `v1_listDriverAudit`.

- [ ] **Step 1: Ajouter les deux fonctions**

Dans `read_callables.js`, avant `module.exports` :

```js
/**
 * Timeline d'un dossier : driver_program_history du livreur, les plus
 * recents d'abord, paginee comme la file.
 */
const v1_listDriverHistory = functions.https.onCall((data, context) => {
  adminCallables.requireAdmin(context);
  const uid = readModels.validateUid((data || {}).uid);
  const page = readModels.validatePageInput(data);
  let query = admin.firestore().collection('driver_program_history')
    .where('driverId', '==', uid)
    .orderBy('at', 'desc')
    .orderBy(admin.firestore.FieldPath.documentId(), 'desc')
    .limit(page.pageSize);
  query = applyCursor(query, page.cursor, 'at');
  return query.get().then((snap) => {
    return {
      items: snap.docs.map((d) => Object.assign({ id: d.id }, d.data())),
      nextCursor: nextCursorFrom(snap, page.pageSize, (docData) => docData.at, 'at')
    };
  }).catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});

/**
 * Journal d'audit : global sans driverId, filtre sur un dossier avec. Les
 * lignes anterieures a la retouche du champ driverId restent visibles du
 * global, jamais du filtre — assume (spec §4.4).
 */
const v1_listDriverAudit = functions.https.onCall((data, context) => {
  adminCallables.requireAdmin(context);
  const page = readModels.validatePageInput(data);
  let driverId = null;
  if (data !== undefined && data !== null && data.driverId !== undefined && data.driverId !== null) {
    driverId = readModels.validateUid(data.driverId);
  }
  let query = admin.firestore().collection('driver_audit_log')
    .orderBy('at', 'desc')
    .orderBy(admin.firestore.FieldPath.documentId(), 'desc')
    .limit(page.pageSize);
  if (driverId !== null) {
    query = query.where('driverId', '==', driverId);
  }
  query = applyCursor(query, page.cursor, 'at');
  return query.get().then((snap) => {
    return {
      items: snap.docs.map((d) => Object.assign({ id: d.id }, d.data())),
      nextCursor: nextCursorFrom(snap, page.pageSize, (docData) => docData.at, 'at')
    };
  }).catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
```

Ajouter au `module.exports` :

```js
  v1_listDriverHistory: v1_listDriverHistory,
  v1_listDriverAudit: v1_listDriverAudit
```

- [ ] **Step 2: Exporter dans `index.js`**

```js
exports.v1_listDriverHistory = driverProgramRead.v1_listDriverHistory
exports.v1_listDriverAudit = driverProgramRead.v1_listDriverAudit
```

- [ ] **Step 3: Vérifier le lint et la non-régression**

Run: `npm run lint` puis `npm test`
Expected: lint sans erreur, tous les tests passent

- [ ] **Step 4: Commit**

```bash
git add functions/products/driver_program/read_callables.js functions/index.js
git commit -m "feat(driver-program): callables de lecture — timeline et journal d'audit"
```

---

### Task 12: `read_callables.js` — la file (`v1_listDriverDossiers`)

**Files:**
- Modify: `functions/products/driver_program/read_callables.js`, `functions/index.js`

**Interfaces:**
- Consumes: `validateListInput`, `routeSearch`, `normalizeCodeTerm`, `normalizeSearchName`, `buildDossierRow`, `applyCursor`, `nextCursorFrom`.
- Produces: `v1_listDriverDossiers` — le contrat exact est au §4.1 de la spec.

- [ ] **Step 1: Vérifier le schéma de la collection `zone`**

Le nom de zone affiché vient de la collection existante `zone`. Vérifier le nom réel de son champ :

Run (depuis `Order Tracking Firebase Function/functions/`) :

```bash
node -e 'const a=require("firebase-admin");a.initializeApp({credential:a.credential.cert(require("./serviceAccountKey.json"))});a.firestore().collection("zone").limit(3).get().then(s=>s.docs.forEach(d=>console.log(d.id, JSON.stringify(d.data()))))'
```

Expected: trois lignes `id {...}`. Noter le champ qui porte le nom (attendu : `name`). Si le champ s'appelle autrement, remplacer `name` dans la ligne `zonesById[d.id] = d.data().name` du Step 3 par le vrai nom.

- [ ] **Step 2: Ajouter la fonction**

Dans `read_callables.js`, avant `module.exports` :

```js
/**
 * La file des dossiers (§4.1 de la spec) : filtrable par statut et par zone,
 * cherchable par nom / code / telephone (route par la forme du terme),
 * triee par anciennete croissante, paginee par curseur.
 *
 * Le filtre zone porte sur profile.primaryZoneId — source de verite unique
 * de la zone du programme. La collection zone est lue en entier (7
 * documents) pour resoudre le nom affiche.
 */
// Sentinelle de fin de plage pour une requete de prefixe Firestore : le plus
// grand point de code Unicode valide, garantit qu'aucune valeur reelle ne le
// depasse. Construite par code plutot qu'un litteral '\uf8ff' dans une
// chaine : ce caractere de la zone Unicode privee est invisible dans la
// plupart des terminaux et editeurs, ce qui rend un litteral inline trompeur
// a relire (il peut sembler absent alors qu'il est present, ou l'inverse).
const PREFIX_SENTINEL = String.fromCharCode(0xf8ff);

const v1_listDriverDossiers = functions.https.onCall((data, context) => {
  adminCallables.requireAdmin(context);
  const input = readModels.validateListInput(data);
  const db = admin.firestore();
  let query = db.collection('driver_program')
    .orderBy('dates.appliedAt', 'asc')
    .orderBy(admin.firestore.FieldPath.documentId(), 'asc')
    .limit(input.pageSize);

  if (input.status !== null) {
    query = query.where('status', '==', input.status);
  }
  if (input.zoneId !== null) {
    query = query.where('profile.primaryZoneId', '==', input.zoneId);
  }
  if (input.search !== null) {
    const kind = readModels.routeSearch(input.search);
    if (kind === 'code') {
      const term = readModels.normalizeCodeTerm(input.search);
      query = query.where('driverCode', '>=', term).where('driverCode', '<', term + PREFIX_SENTINEL);
    } else if (kind === 'phone') {
      const term = input.search.trim();
      query = query.where('profile.phone', '>=', term).where('profile.phone', '<', term + PREFIX_SENTINEL);
    } else {
      const term = readModels.normalizeSearchName(input.search, '');
      query = query.where('searchName', '>=', term).where('searchName', '<', term + PREFIX_SENTINEL);
    }
  }
  query = applyCursor(query, input.cursor, 'appliedAt');
  return Promise.all([query.get(), db.collection('zone').get()]).then((results) => {
    const zonesById = {};
    results[1].docs.forEach((d) => {
      zonesById[d.id] = d.data().name || null;
    });
    return {
      items: results[0].docs.map((d) => readModels.buildDossierRow(d, zonesById)),
      nextCursor: nextCursorFrom(results[0], input.pageSize,
        (docData) => docData.dates.appliedAt, 'appliedAt')
    };
  }).catch((e) => { throw new functions.https.HttpsError('failed-precondition', e.message); });
});
```

Ajouter au `module.exports` :

```js
  v1_listDriverDossiers: v1_listDriverDossiers
```

- [ ] **Step 3: Exporter dans `index.js`**

```js
exports.v1_listDriverDossiers = driverProgramRead.v1_listDriverDossiers
```

- [ ] **Step 4: Vérifier le lint et la non-régression**

Run: `npm run lint` puis `npm test`
Expected: lint sans erreur, tous les tests passent

- [ ] **Step 5: Commit**

```bash
git add functions/products/driver_program/read_callables.js functions/index.js
git commit -m "feat(driver-program): callable de lecture — la file des dossiers"
```

---

### Task 13: Index composites — fichier et déploiement

**Files:**
- Modify: `Firebase Indexing/firestore_indexes.json`

**Interfaces:**
- Consumes: rien. Produit la couverture d'index des requêtes des Tasks 9-12. Sans eux, chaque requête filtrée de la file échoue — les fonctions déjà déployées importent peu, l'index doit exister avant le premier appel.

- [ ] **Step 1: Sauvegarder le fichier (dossier non versionné)**

```bash
cp "c:/Projet/AUTRE/Nouveau dossier/Firebase Indexing/firestore_indexes.json" "c:/Projet/AUTRE/Nouveau dossier/Firebase Indexing/firestore_indexes.backup-20260831.json"
```

- [ ] **Step 2: Ajouter les sept index**

Dans `firestore_indexes.json`, le tableau `"indexes"` suit ce format exact (même `density` et `queryScope` que les 192 entrées existantes). Ajouter les sept blocs suivants dans le tableau `"indexes"`, séparés par des virgules. **Ne pas ajouter d'index « nu »** (un seul champ métier + `__name__`, sans clause d'égalité) pour la file sans filtre ou le journal global : Firestore couvre déjà ce cas par son indexation automatique par champ et **refuse au déploiement** (`HTTP 400 : this index is not necessary, configure using single field index controls`) tout composite qui ne fait que ça — découvert en exécutant cette tâche le 2026-08-31, deux blocs de ce type ont dû être retirés après un premier déploiement en échec :

```json
    {
      "collectionGroup": "driver_program",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "dates.appliedAt", "order": "ASCENDING" },
        { "fieldPath": "__name__", "order": "ASCENDING" }
      ],
      "density": "SPARSE_ALL"
    },
    {
      "collectionGroup": "driver_program",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "profile.primaryZoneId", "order": "ASCENDING" },
        { "fieldPath": "dates.appliedAt", "order": "ASCENDING" },
        { "fieldPath": "__name__", "order": "ASCENDING" }
      ],
      "density": "SPARSE_ALL"
    },
    {
      "collectionGroup": "driver_program",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "searchName", "order": "ASCENDING" },
        { "fieldPath": "dates.appliedAt", "order": "ASCENDING" },
        { "fieldPath": "__name__", "order": "ASCENDING" }
      ],
      "density": "SPARSE_ALL"
    },
    {
      "collectionGroup": "driver_program",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "driverCode", "order": "ASCENDING" },
        { "fieldPath": "dates.appliedAt", "order": "ASCENDING" },
        { "fieldPath": "__name__", "order": "ASCENDING" }
      ],
      "density": "SPARSE_ALL"
    },
    {
      "collectionGroup": "driver_program",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "profile.phone", "order": "ASCENDING" },
        { "fieldPath": "dates.appliedAt", "order": "ASCENDING" },
        { "fieldPath": "__name__", "order": "ASCENDING" }
      ],
      "density": "SPARSE_ALL"
    },
    {
      "collectionGroup": "driver_program_history",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "driverId", "order": "ASCENDING" },
        { "fieldPath": "at", "order": "DESCENDING" },
        { "fieldPath": "__name__", "order": "DESCENDING" }
      ],
      "density": "SPARSE_ALL"
    },
    {
      "collectionGroup": "driver_audit_log",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "driverId", "order": "ASCENDING" },
        { "fieldPath": "at", "order": "DESCENDING" },
        { "fieldPath": "__name__", "order": "DESCENDING" }
      ],
      "density": "SPARSE_ALL"
    }
```

(Sept blocs : `driver_program` ×5, un par filtre égalité — `status`, `profile.primaryZoneId`, `searchName`, `driverCode`, `profile.phone`, chacun composé avec `dates.appliedAt` puis `__name__` ; `driver_program_history` et `driver_audit_log` filtrés par `driverId`, `at` desc.)

- [ ] **Step 3: Valider le JSON et vérifier que le projet Firebase est bien ciblé**

Run (depuis `Firebase Indexing/`) :

```bash
node -e 'JSON.parse(require("fs").readFileSync("firestore_indexes.json","utf8")); console.log("JSON valide")'
ls firebase.json
```

Expected: `JSON valide` et `firebase.json` présent (le dossier a déjà servi au déploiement des 192 index).

- [ ] **Step 4: Déployer les index**

Run (depuis `Firebase Indexing/`) :

```bash
firebase deploy --only firestore:indexes --project rapyogo-2bccd
```

Expected: déploiement réussi. Si Firestore rejette un index avec « this index is not necessary, configure using single field index controls », c'est qu'il duplique l'indexation automatique — le retirer et redéployer (voir Step 2). La construction des index prend quelques minutes ; vérifier dans la console que les sept apparaissent « building » puis « enabled » avant de déployer les fonctions (Task 14). Un échec « An unexpected error has occurred » est transitoire : relancer.

**Fait le 2026-08-31** : les deux blocs « nus » initialement envisagés (couvrant la file sans filtre et le journal global) ont été rejetés au premier déploiement pour la raison ci-dessus, retirés, et le redéploiement des 7 index restants a réussi (`+ Deploy complete!`).

- [ ] **Step 5: Commit**

Le dossier `Firebase Indexing/` n'est pas un dépôt git : rien à committer. La sauvegarde du Step 1 fait foi.

---

### Task 14: Déploiement des fonctions et vérification de bout en bout

**Files:**
- Create: `functions/verify_read_callables.js`

**Interfaces:**
- Consumes: les 7 fonctions déployées. Produit la preuve que chaque contrat de la spec répond.

- [ ] **Step 1: Écrire le script de vérification**

Créer `functions/verify_read_callables.js` (nom sans `.test.` — il ne sera pas exécuté par `node --test`) :

```js
'use strict';

// Script de verification des callables de lecture, apres deploiement.
// Usage : node verify_read_callables.js  (depuis functions/)
// Exige serviceAccountKey.json (comme index.js) et les fonctions deployees.
// L'uid admin-1 est celui du panel (claim admin, voir HANDOFF-FRONT).
// La cle API vient du google-services.json du driver (projet rapyogo-2bccd).

const admin = require('firebase-admin');
const fs = require('fs');

admin.initializeApp({ credential: admin.credential.cert(require('./serviceAccountKey.json')) });

const ADMIN_UID = 'admin-1';
const API_KEY = JSON.parse(fs.readFileSync('../../driver/android/app/google-services.json', 'utf8'))
  .client[0].api_key[0].current_key;
const BASE = 'https://us-central1-rapyogo-2bccd.cloudfunctions.net/';

function callFunction(name, data, idToken) {
  return fetch(BASE + name, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + idToken },
    body: JSON.stringify({ data: data })
  }).then((r) => r.json()).then((body) => {
    if (body.error) {
      throw new Error(name + ' : ' + JSON.stringify(body.error));
    }
    return body.result;
  });
}

function check(label, condition) {
  if (condition !== true) {
    throw new Error('ECHEC : ' + label);
  }
  console.log('OK : ' + label);
}

admin.auth().createCustomToken(ADMIN_UID, { role: 'admin' }).then((customToken) => {
  return fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=' + API_KEY, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true })
  }).then((r) => r.json()).then((body) => {
    if (!body.idToken) {
      throw new Error('Echange de token impossible : ' + JSON.stringify(body));
    }
    return body.idToken;
  });
}).then((idToken) => {
  let dossierUid = null;
  return callFunction('v1_listDriverDossiers', {}, idToken).then((result) => {
    check('v1_listDriverDossiers rend items et nextCursor', Array.isArray(result.items) && ('nextCursor' in result));
    dossierUid = result.items.length > 0 ? result.items[0].uid : null;
    return callFunction('v1_listDriverDossiers', { status: 'CANDIDATURE', pageSize: 5 }, idToken);
  }).then((result) => {
    check('v1_listDriverDossiers filtre par statut', Array.isArray(result.items));
    return callFunction('v1_getProgramSettings', {}, idToken);
  }).then((result) => {
    check('v1_getProgramSettings rend un objet', typeof result === 'object' && result !== null);
    return callFunction('v1_listTrainingModules', {}, idToken);
  }).then((result) => {
    check('v1_listTrainingModules rend items', Array.isArray(result.items));
    return callFunction('v1_listTrainingQuestions', {}, idToken);
  }).then((result) => {
    check('v1_listTrainingQuestions rend items', Array.isArray(result.items));
    const avecCorrige = result.items.filter((q) => Number.isInteger(q.correctIndex)).length;
    check('v1_listTrainingQuestions rend le corrige (' + avecCorrige + '/' + result.items.length + ')',
      result.items.length === 0 || avecCorrige > 0);
    return callFunction('v1_listDriverAudit', {}, idToken);
  }).then((result) => {
    check('v1_listDriverAudit global rend items', Array.isArray(result.items));
    if (dossierUid === null) {
      console.log('AVERTISSEMENT : la file est vide — verifications du dossier sautees.');
      console.log('Creez un dossier via v1_applyAsDriver ou lancez la reprise avant de relancer.');
      return null;
    }
    return callFunction('v1_getDriverDossier', { uid: dossierUid }, idToken);
  }).then((result) => {
    if (result === null) {
      return null;
    }
    check('v1_getDriverDossier rend program et documents', result.program !== undefined && Array.isArray(result.documents));
    return callFunction('v1_listDriverHistory', { uid: dossierUid }, idToken);
  }).then((result) => {
    if (result === null) {
      return null;
    }
    check('v1_listDriverHistory rend items', Array.isArray(result.items));
    return callFunction('v1_listDriverAudit', { driverId: dossierUid }, idToken);
  }).then((result) => {
    if (result === null) {
      return null;
    }
    check('v1_listDriverAudit filtre par dossier', Array.isArray(result.items));
    console.log('Toutes les verifications passent.');
    return null;
  });
}).catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
```

- [ ] **Step 2: Vérifier le lint (le script est couvert par `eslint .`)**

Run: `npm run lint`
Expected: lint sans erreur

- [ ] **Step 3: Déployer les sept fonctions en cible**

Run (depuis `Order Tracking Firebase Function/`) :

```bash
firebase deploy --only functions:v1_listDriverDossiers,functions:v1_getDriverDossier,functions:v1_listDriverHistory,functions:v1_listDriverAudit,functions:v1_getProgramSettings,functions:v1_listTrainingModules,functions:v1_listTrainingQuestions --project rapyogo-2bccd
```

Expected: déploiement réussi des sept fonctions. Jamais de `--only functions` global : `helloWorld` et `sendNewOrderNotification` ne doivent pas être touchées.

- [ ] **Step 4: Lancer la vérification**

Run (depuis `functions/`) :

```bash
node verify_read_callables.js
```

Expected: une série de lignes `OK : ...` et `Toutes les verifications passent.` (ou l'avertissement file vide, auquel cas créer un dossier de test via `v1_applyAsDriver` avec un compte authentifié puis relancer).

- [ ] **Step 5: Commit**

```bash
git add functions/verify_read_callables.js
git commit -m "feat(driver-program): script de verification des callables de lecture"
```

- [ ] **Step 6: Mettre à jour le journal de bord**

Ajouter une entrée au `customer/docs/HANDOFF.md` (non commité, comme les sessions précédentes) : les sept fonctions déployées, leurs contrats en une ligne, les index ajoutés, le prérequis posé à la reprise (`dates.appliedAt` + `searchName` sur chaque dossier repris), et le fait que le script `verify_read_callables.js` sert de test de fumée après tout déploiement futur.

---

## Vérification finale (après la Task 14)

- `npm test` : tous les tests passent (les 82 existants + les nouveaux de `read_models.test.js`).
- `npm run lint` : aucune erreur.
- Les sept index composites sont « enabled » dans la console Firebase.
- `node verify_read_callables.js` : toutes les lignes `OK`.
- La branche `feat/callables-lecture-admin` porte 13 commits, prête au merge sur `master`.
