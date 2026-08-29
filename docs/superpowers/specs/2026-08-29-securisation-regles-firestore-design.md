# Sécurisation des accès Firestore de la plateforme Viteat

**Date :** 2026-08-29
**Statut :** conception, en attente de relecture
**Périmètre :** `rapyogo-2bccd` (production), Admin Panel, Restaurant Panel, apps `customer` et `driver`

---

## 1. Le problème

Les règles de sécurité Firestore publiées sur `rapyogo-2bccd` sont ouvertes :

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Accès complet à tous (non sécurisé - à utiliser uniquement en test)
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

Release `projects/rapyogo-2bccd/releases/cloud.firestore`, publiée le **2025-05-29**, toujours
active au 2026-08-29. Le commentaire est celui du template : ces règles n'ont jamais été refermées.

La clé API Firebase est présente dans l'APK des deux applications et dans le JavaScript des deux
panels. Elle est extractible sans compétence particulière. Avec elle, **n'importe qui sur Internet
peut lire et écrire l'intégralité de la base** :

| Collection | Ce qu'un tiers peut faire aujourd'hui |
|---|---|
| `users` | lire les coordonnées de tous les clients et livreurs ; modifier n'importe quel profil |
| `wallet` | créditer un solde arbitraire |
| `payouts`, `driver_payouts` | créer une demande de retrait |
| `restaurant_orders` | lire toutes les commandes ; en passer une à `Order Completed` |
| `settings` | modifier la configuration des quatre applications à chaud |

### Comment cela a été découvert

En concevant la **preuve de livraison** (empêcher un livreur de clôturer une commande sans l'avoir
remise). Le dispositif envisagé — un code remis par le client, vérifié avant clôture — s'est révélé
sans effet : tant que l'écriture directe reste ouverte, l'application peut écrire `Order Completed`
sans passer par la vérification, et le code lui-même est lisible dans le document de commande.

**La preuve de livraison est donc reportée après ce chantier.** Elle est spécifiée séparément.

---

## 2. Contraintes

1. **Pas de staging.** `rapyogo-2bccd` porte les vrais utilisateurs et les vraies commandes. Toute
   erreur de règle casse un flux en pleine journée de service.
2. **Quatre clients directs**, plus 210 vues web qui parlent à Firestore depuis le navigateur
   (161 Admin Panel, 49 Restaurant Panel). Toutes sont soumises aux règles.
3. **Deux dépôts git seulement** (`customer`, `driver`). Les panels et les Cloud Functions n'ont
   aucun historique : toute modification y est immédiatement définitive. Sauvegarde préalable
   obligatoire.

### État de l'authentification par client

| Client | Identité Firebase | Détail |
|---|---|---|
| App cliente | ✅ Firebase Auth | rôle `customer` |
| App livreur | ✅ Firebase Auth | rôle `driver` |
| Restaurant Panel | ⚠️ partielle | `signInWithEmailAndPassword` à la connexion (`auth/login.blade.php:355`) — session existante, portée à vérifier |
| Admin Panel | ❌ **aucune** | 161 vues écrivent en anonyme |

C'est le point dur : **l'Admin Panel n'a aucune identité Firebase.** Toute règle plus stricte que
`if true` le casse intégralement, et il n'y a personne à qui accorder des droits.

### Filets de sécurité posés le 2026-08-29 (préalable, déjà fait)

| Réglage | Avant | Après |
|---|---|---|
| Sauvegarde planifiée | aucune | quotidienne, rétention 7 jours |
| Point-in-time recovery | 1 h | **7 jours**, à la minute près |
| Protection contre la suppression | désactivée | activée |

Un export hors ligne complet a par ailleurs été produit dans
`_backup_firestore_20260829/` (hors dépôt git).

---

## 3. Architecture existante — points d'injection

### Admin Panel

L'initialisation Firebase est dans **`public/js/jquery.validate.js` lignes 1-13**, un fichier qui
porte le nom de la librairie jQuery Validate :

```js
var firebaseConfig = {
    apiKey: $.decrypt($.cookie('XSRF-TOKEN-AK')),
    // ...
}
firebase.initializeApp(firebaseConfig);
```

La configuration arrive par des cookies posés dans `app/Providers/AppServiceProvider.php:19`, via
`bin2hex(env('FIREBASE_APIKEY'))` — de l'hexadécimal, pas du chiffrement.

Deux conséquences favorables :

- **Un canal Laravel → JavaScript existe déjà** au chargement de chaque page. Le jeton
  d'authentification empruntera le même chemin.
- **`firebase-auth-compat.js` est déjà chargé** (`layouts/app.blade.php:300`). Aucune dépendance
  nouvelle côté navigateur.

### Les deux panels disposent du SDK admin PHP

`kreait/firebase-php ^7.15` est dans le `composer.json` des deux panels. Il sait émettre des
**custom tokens** (`createCustomToken($uid, $claims)`). C'est ce qui rend l'approche réaliste sans
toucher les 210 vues.

---

## 4. Approche retenue

**Donner une identité Firebase aux panels, puis refermer les règles en deux paliers.**

Le principe : les vues ne changent pas. Une seule authentification, faite une fois au chargement,
avant tout accès Firestore. Les règles s'appuient ensuite sur l'identité et sur un *claim* de rôle.

### Palier 1 — identité et fermeture de la porte publique

**Admin Panel**
1. Une route Laravel authentifiée émet un custom token via `kreait`, portant le claim
   `role: "admin"`, pour l'utilisateur administrateur connecté.
2. Le jeton est transmis au JavaScript par le canal existant (même mécanisme que les cookies de
   configuration, ou une variable injectée dans le layout).
3. `jquery.validate.js` fait `firebase.auth().signInWithCustomToken(token)` **immédiatement après**
   `initializeApp`, et les accès Firestore attendent la résolution de cette promesse.

**Restaurant Panel**
La session Firebase existe déjà à la connexion. Il faut vérifier qu'elle est **persistante** et
présente sur toutes les vues, et lui ajouter le claim `role: "vendor"` + `vendorId` par le même
mécanisme de custom token — la connexion par email seule ne porte aucun rôle.

**Applications Flutter**
Aucune modification. Elles sont déjà authentifiées.

**Règles déployées au palier 1**

```
match /{document=**} {
  allow read, write: if request.auth != null;
}
```

**Ce que ce palier apporte réellement :** il ferme l'accès **anonyme** — les scans automatisés et la
lecture de la base clients par quelqu'un qui a simplement extrait la clé de l'APK.

**Ce qu'il n'apporte pas :** l'inscription est libre dans l'application cliente. N'importe qui peut
obtenir un compte en trente secondes, et retrouver alors les droits d'aujourd'hui. **Le palier 1
n'est pas le verrou** — il ferme la porte tout de suite sans rien casser, et il installe l'identité
sur laquelle le palier 2 s'appuiera.

### Palier 2 — règles par rôle

Règles fines sur les collections qui portent l'argent et la donnée personnelle. Le reste — catalogue,
menus, catégories, zones, `on_boarding` — reste en lecture large : c'est du contenu public, le
fermer n'apporte rien et casserait la navigation avant connexion.

| Collection | Lecture | Écriture |
|---|---|---|
| `users` | soi-même ; `admin` ; `vendor` limité à ses livreurs ; `driver` limité au client de sa commande en cours | soi-même (champs non sensibles) ; `admin` |
| `wallet`, `payouts`, `driver_payouts` | soi-même ; `admin` | **Cloud Function uniquement** |
| `restaurant_orders` | client concerné ; livreur assigné ; `vendor` propriétaire ; `admin` | transitions d'état contrôlées selon le rôle |
| `settings` | tous (authentifiés) | `admin` |
| `chat` | participants ; `admin` | participants |
| `vendors`, `vendor_products`, `menu_items`, `zone`, `currencies`, `on_boarding`, `coupons` | large | `vendor` propriétaire ; `admin` |
| `foods_review`, `favorite_*` | large | auteur |

Le détail par collection sera établi à l'implémentation, à partir des sites d'appel réels des quatre
clients — pas depuis cette table, qui est une intention.

---

## 5. Ce que nous ne faisons pas

- **Réécrire les 210 vues** pour passer par le backend Laravel (approche « tout par le SDK admin »).
  Le plus propre en théorie, irréaliste en pratique, et sans effet sur les deux apps Flutter qui
  resteront des clients directs.
- **Fermer le catalogue public.** Menus, restaurants et zones doivent rester lisibles avant
  connexion, sinon l'application cliente n'affiche plus rien à un visiteur.
- **Écrire les 33 collections d'un seul jet et déployer en une fois.** Sans staging, la première
  erreur casse un flux sans qu'on sache lequel.
- **Corriger l'obfuscation par cookies** de la configuration Firebase. C'est cosmétique : une
  configuration Firebase web n'est pas un secret, elle est publique par conception. Ce qui protège,
  ce sont les règles.

---

## 6. Points à vérifier avant l'implémentation

Ces incertitudes ne bloquent pas la conception, mais doivent être levées avant d'écrire le code :

1. **Les administrateurs ont-ils un compte Firebase Auth ?** Le custom token doit porter un `uid`.
   S'il n'existe pas de compte correspondant à l'administrateur Laravel, il faut décider si le token
   référence un uid dédié créé à la volée, ou l'uid d'un utilisateur `users` existant.
2. **Portée de la session Firebase du Restaurant Panel** : persiste-t-elle entre les pages, ou
   n'existe-t-elle qu'au moment de la connexion ?
3. **Le Restaurant Panel tourne-t-il en production ailleurs que sur cette machine ?** Son `.env`
   porte `APP_ENV=local` / `APP_URL=http://localhost`. Si la production est sur un autre serveur,
   c'est là qu'il faut appliquer les modifications.
4. **Les Cloud Functions ne sont pas concernées** : le SDK admin ignore les règles. À confirmer pour
   `deliveryDispatch`, qui écrit dans `users` et `restaurant_orders`.
5. **`geofirestore`** est utilisé par l'Admin Panel pour les requêtes géographiques. Vérifier que ses
   requêtes passent les règles envisagées.

---

## 7. Test et déploiement

**Test** : émulateur Firestore (`firebase emulators:start --only firestore`) avec un jeu de tests de
règles couvrant, pour chaque rôle, un cas autorisé et un cas refusé. Les règles ne sont pas
déployées avant que ces tests passent.

**Déploiement** : à une heure creuse, palier par palier, avec vérification manuelle des quatre
applications après chaque déploiement.

**Retour arrière** : le ruleset actuel est conservé dans ce dépôt avant toute modification. Un
retour arrière est un redéploiement de ce fichier — quelques secondes. En cas de dommage sur les
données, PITR permet de revenir à la minute près sur 7 jours.

**Critère de réussite du palier 1** : les quatre applications fonctionnent normalement, et une
requête Firestore anonyme portant la clé API publique est refusée.

---

## 8. Suite

Une fois le palier 2 en place, reprendre la conception de la **preuve de livraison**, qui devient
alors applicable : le code de remise pourra être caché au livreur, et la transition vers
`Order Completed` réservée à une Cloud Function.
