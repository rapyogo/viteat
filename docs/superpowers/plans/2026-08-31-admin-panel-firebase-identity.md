# Identité Firebase de l'Admin Panel — Palier 1 (claim admin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Donner à l'Admin Panel une identité Firebase Auth portant le claim `role: "admin"`, pour que les 6 Cloud Functions d'administration du programme Partenaires Livreurs (`v1_reviewDocument`, `v1_recordPracticalTest`, `v1_suspendDriver`, `v1_reinstateDriver`, `v1_rejectApplication`, `v1_updateProgramSettings`), qui exigent toutes `request.auth.token.role === 'admin'`, deviennent appelables.

**Architecture:** Un service Laravel (`FirebaseCustomTokenService`) émet un custom token via `kreait/firebase-php`, à partir du compte de service déjà présent dans `storage/app/firebase/credentials.json`. Le token est injecté dans le HTML de chaque page rendue (via le view composer déjà utilisé dans `AppServiceProvider::boot()`), sur le même principe que les cookies de configuration Firebase existants — pas d'aller-retour AJAX supplémentaire. Côté navigateur, `jquery.validate.js` (qui fait déjà `firebase.initializeApp`) enchaîne avec `signInWithCustomToken` dès que le token est présent. Les 161 vues existantes ne changent pas.

**Tech Stack:** Laravel 10 (PHP 8.2), `kreait/firebase-php ^7.23` (déjà dans `vendor/`), Firebase JS SDK 9.23.0 compat (déjà chargé dans le layout), PHPUnit.

**Spec:** `customer/docs/superpowers/specs/2026-08-29-securisation-regles-firestore-design.md` (section 4, « Palier 1 — Admin Panel », §6.1)

**Portée de ce plan (volontairement étroite) :** ce plan couvre uniquement l'identité Firebase de l'Admin Panel avec le claim `admin` — le prérequis qui débloque les 6 Cloud Functions d'administration. Il ne touche PAS au déploiement des règles Firestore tightening (`allow read, write: if request.auth != null`, palier 1 complet de la spec) ni au Restaurant Panel : ce sont des chantiers distincts, à traiter séparément une fois ce socle en place.

## Global Constraints

- **`Admin Panel/` n'est pas un dépôt git.** Toute modification y est immédiatement définitive. Pas d'étape « commit » dans ce plan — la sauvegarde ciblée de la tâche 1 est le seul filet de sécurité (un backup complet daté du 2026-08-29 existe déjà dans `_backup_admin_panel_20260829/` comme filet plus large).
- **`rapyogo-2bccd` est la production, il n'y a pas de staging.** Toute erreur casse l'Admin Panel en pleine journée de service.
- **Le compte de service `storage/app/firebase/credentials.json` existe déjà** (déposé le 2026-08-24, utilisé aujourd'hui uniquement pour l'envoi FCM via `Google_Client` dans `AdvertisementsController`, `BookTableController`, `OrderController`, `NotificationController`). Ne pas le déplacer, ne jamais l'exposer sous `public/`, ne jamais l'afficher dans un log ou une réponse HTTP.
- **Tous les messages destinés à un humain sont en français** (messages d'erreur, logs, commentaires si nécessaires).
- **`MySQL (monsite3) est arrêté sur cette machine`** au moment d'écrire ce plan. Les tests de ce plan n'en dépendent pas (voir Task 1) ; la vérification manuelle de la tâche 3 nécessite de le démarrer.
- **PHP n'est pas dans le PATH** : utiliser `C:\xampp\xampp\php\php.exe` explicitement pour toute commande `php`/`artisan`/`phpunit`.

---

## Structure des fichiers

| Fichier | Responsabilité |
|---|---|
| `app/Services/FirebaseCustomTokenService.php` | **Nouveau.** Émet le custom token Firebase (`uid`, claim `role: admin`) pour un `User` Laravel donné. Seul point du code qui touche `kreait/firebase-php` pour l'authentification. |
| `app/Providers/AppServiceProvider.php` | Modifié. Le view composer existant (`boot()`) calcule `$firebaseAdminToken` et l'injecte dans toutes les vues. |
| `resources/views/layouts/app.blade.php` | Modifié. Une ligne insérée avant l'inclusion de `jquery.validate.js` : expose le token au JavaScript. |
| `public/js/jquery.validate.js` | Modifié. Après `firebase.initializeApp(...)`, appelle `signInWithCustomToken` si un token est présent. |
| `tests/Feature/FirebaseCustomTokenServiceTest.php` | **Nouveau.** Vérifie la structure du JWT émis (uid, claim role), sans dépendance réseau ni base de données. |

---

### Task 1: Service d'émission du custom token

**Files:**
- Create: `app/Services/FirebaseCustomTokenService.php`
- Test: `tests/Feature/FirebaseCustomTokenServiceTest.php`
- Backup: copies horodatées des fichiers touchés par ce plan

**Interfaces:**
- Consumes: `App\Models\User` (propriété `id`), fichier `storage/app/firebase/credentials.json` (déjà présent)
- Produces: `App\Services\FirebaseCustomTokenService::forUser(User $user): string` — retourne le JWT du custom token, utilisé par Task 2.

- [ ] **Step 1: Sauvegarder les fichiers que ce plan va modifier**

Ces fichiers n'ont aucun historique git. Sauvegarde ciblée avant toute écriture (le backup complet du 2026-08-29 existe déjà comme filet plus large, celui-ci est le filet précis de cette session) :

```bash
cd "c:/Projet/AUTRE/Nouveau dossier"
mkdir -p "_backup_admin_panel_firebase_auth_20260831"
cp "Admin Panel/app/Providers/AppServiceProvider.php" "_backup_admin_panel_firebase_auth_20260831/AppServiceProvider.php"
cp "Admin Panel/resources/views/layouts/app.blade.php" "_backup_admin_panel_firebase_auth_20260831/app.blade.php"
cp "Admin Panel/public/js/jquery.validate.js" "_backup_admin_panel_firebase_auth_20260831/jquery.validate.js"
ls "_backup_admin_panel_firebase_auth_20260831/"
```

Attendu : les trois fichiers sont listés.

- [ ] **Step 2: Écrire le test qui échoue**

```php
<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\FirebaseCustomTokenService;
use Tests\TestCase;

class FirebaseCustomTokenServiceTest extends TestCase
{
    public function test_it_issues_a_custom_token_carrying_the_admin_claim(): void
    {
        $user = new User();
        $user->id = 42;

        $jwt = (new FirebaseCustomTokenService())->forUser($user);

        $parts = explode('.', $jwt);
        $this->assertCount(3, $parts, 'un JWT a trois segments');

        $payload = json_decode(
            base64_decode(strtr($parts[1], '-_', '+/')),
            true
        );

        $this->assertSame('admin-42', $payload['uid']);
        $this->assertSame('admin', $payload['claims']['role']);
    }

    public function test_it_produces_a_distinct_uid_per_user(): void
    {
        $userA = new User();
        $userA->id = 1;
        $userB = new User();
        $userB->id = 2;

        $service = new FirebaseCustomTokenService();

        $payloadOf = function (string $jwt): array {
            $parts = explode('.', $jwt);
            return json_decode(base64_decode(strtr($parts[1], '-_', '+/')), true);
        };

        $uidA = $payloadOf($service->forUser($userA))['uid'];
        $uidB = $payloadOf($service->forUser($userB))['uid'];

        $this->assertNotSame($uidA, $uidB);
    }
}
```

Ce test n'insère rien en base (`User` est instancié en mémoire, jamais sauvegardé) : il fonctionne même MySQL arrêté. La signature RS256 se fait localement avec la clé privée du fichier de compte de service, sans appel réseau.

- [ ] **Step 3: Lancer le test, vérifier qu'il échoue**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Admin Panel"
"C:\xampp\xampp\php\php.exe" artisan test --filter=FirebaseCustomTokenServiceTest
```

Attendu : ÉCHEC — `Class "App\Services\FirebaseCustomTokenService" not found`.

- [ ] **Step 4: Écrire l'implémentation minimale**

```php
<?php

namespace App\Services;

use App\Models\User;
use Kreait\Firebase\Factory;
use RuntimeException;

class FirebaseCustomTokenService
{
    private const CREDENTIALS_PATH = 'app/firebase/credentials.json';

    public function forUser(User $user): string
    {
        $credentialsPath = storage_path(self::CREDENTIALS_PATH);

        if (!is_file($credentialsPath)) {
            throw new RuntimeException(
                'Compte de service Firebase introuvable : ' . $credentialsPath
            );
        }

        $auth = (new Factory())
            ->withServiceAccount($credentialsPath)
            ->createAuth();

        $token = $auth->createCustomToken('admin-' . $user->id, ['role' => 'admin']);

        return $token->toString();
    }
}
```

- [ ] **Step 5: Lancer le test, vérifier qu'il passe**

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Admin Panel"
"C:\xampp\xampp\php\php.exe" artisan test --filter=FirebaseCustomTokenServiceTest
```

Attendu : 2 tests, PASS.

Pas d'étape « commit » — ce dossier n'a pas de dépôt git (voir Global Constraints). La sauvegarde de l'étape 1 tient lieu de point de retour.

---

### Task 2: Injection du token dans les vues rendues

**Files:**
- Modify: `app/Providers/AppServiceProvider.php`
- Modify: `resources/views/layouts/app.blade.php:308`

**Interfaces:**
- Consumes: `App\Services\FirebaseCustomTokenService::forUser(User $user): string` (Task 1)
- Produces: variable de vue `$firebaseAdminToken` (string|null), variable JavaScript globale `window.__FIREBASE_ADMIN_TOKEN__`, consommées par Task 3.

- [ ] **Step 1: Ajouter `$firebaseAdminToken` au view composer existant**

Dans `app/Providers/AppServiceProvider.php`, le `boot()` actuel (lignes 34-57) contient déjà un `view()->composer('*', ...)`. Le remplacer par :

```php
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Auth;
use App\Helpers\FirestoreHelper;
use App\Services\FirebaseCustomTokenService;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     *
     * @return void
     */
    public function register()
    {
        setcookie('XSRF-TOKEN-AK', bin2hex(env('FIREBASE_APIKEY')), time() + 3600, "/"); 
        setcookie('XSRF-TOKEN-AD', bin2hex(env('FIREBASE_AUTH_DOMAIN')), time() + 3600, "/"); 
        setcookie('XSRF-TOKEN-DU', bin2hex(env('FIREBASE_DATABASE_URL')), time() + 3600, "/"); 
        setcookie('XSRF-TOKEN-PI', bin2hex(env('FIREBASE_PROJECT_ID')), time() + 3600, "/"); 
        setcookie('XSRF-TOKEN-SB', bin2hex(env('FIREBASE_STORAGE_BUCKET')), time() + 3600, "/"); 
        setcookie('XSRF-TOKEN-MS', bin2hex(env('FIREBASE_MESSAAGING_SENDER_ID')), time() + 3600, "/"); 
        setcookie('XSRF-TOKEN-AI', bin2hex(env('FIREBASE_APP_ID')), time() + 3600, "/"); 
        setcookie('XSRF-TOKEN-MI', bin2hex(env('FIREBASE_MEASUREMENT_ID')), time() + 3600, "/"); 
    }
    
    /**
     * Bootstrap any application services.
     *
     * @return void
     */
    public function boot()
    {

        $countries_data = [];
        $get_countries_json = file_get_contents(public_path('countriesdata.json'));
        if($get_countries_json != ''){
            $countries_data = json_decode($get_countries_json);
        }
        
        $openai_settings = FirestoreHelper::getDocument('settings/openai_settings');
        if (!empty($openai_settings)) {
            if (!empty($openai_settings['api_key'])) {
                Config::set('openai.api_key', $openai_settings['api_key']);
            }
            if (!empty($openai_settings['organization'])) {
                Config::set('openai.organization', $openai_settings['organization']);
            }
        }

        view()->composer('*', function ($view) use ($countries_data, $openai_settings) {
            $view->with('countries_data', $countries_data);
            $view->with('openai_settings', $openai_settings);

            $firebaseAdminToken = null;
            if (Auth::check()) {
                try {
                    $firebaseAdminToken = (new FirebaseCustomTokenService())->forUser(Auth::user());
                } catch (\Throwable $e) {
                    logger()->error('Émission du custom token Firebase admin impossible', [
                        'message' => $e->getMessage(),
                    ]);
                }
            }
            $view->with('firebaseAdminToken', $firebaseAdminToken);
        });
    }
}
```

Le `try/catch` est nécessaire ici et nulle part ailleurs dans ce plan : cette closure s'exécute sur **chaque** vue rendue (`'*'`). Une exception non rattrapée y ferait tomber tout l'Admin Panel en erreur 500 sur chaque page si le compte de service devient un jour illisible.

- [ ] **Step 2: Exposer le token au JavaScript dans le layout**

Dans `resources/views/layouts/app.blade.php`, juste avant la ligne 308 (`<script src="{{ asset('js/jquery.validate.js') }}"></script>`), insérer :

```blade
<script>
    window.__FIREBASE_ADMIN_TOKEN__ = @json($firebaseAdminToken ?? null);
</script>
<script src="{{ asset('js/jquery.validate.js') }}"></script>
```

`@json` échappe correctement la valeur pour une insertion sûre dans un `<script>` (Laravel `Illuminate\Support\Js::from`), y compris quand `$firebaseAdminToken` vaut `null` (page de login, avant authentification).

- [ ] **Step 3: Cas déjà vérifié — la page de login**

`resources/views/auth/login.blade.php` est un fichier HTML autonome (pas de `@extends('layouts.app')`) : le bloc ajouté à l'étape 2 n'y est donc pas dupliqué. Elle inclut cependant sa propre balise `<script src="{{ asset('js/jquery.validate.js') }}">` (ligne 145) pour initialiser Firebase avant connexion. Sur cette page, `window.__FIREBASE_ADMIN_TOKEN__` n'est jamais défini (`undefined`) — le test `if (window.__FIREBASE_ADMIN_TOKEN__)` de Task 3 le traite comme faux, donc aucun appel `signInWithCustomToken` n'y est tenté. Rien à modifier ici, c'est le comportement voulu : avant connexion, il n'y a pas d'admin pour qui émettre un token. Aucune action pour cette étape — elle documente une vérification déjà faite, pas un risque ouvert.

Pas d'étape « commit » (voir Global Constraints).

---

### Task 3: Connexion Firebase côté navigateur + vérification manuelle

**Files:**
- Modify: `public/js/jquery.validate.js`

**Interfaces:**
- Consumes: `window.__FIREBASE_ADMIN_TOKEN__` (Task 2)
- Produces: une session Firebase Auth active dans le navigateur, `firebase.auth().currentUser` non nul avec le claim `role: "admin"`, sur laquelle les futures fonctions d'administration s'appuieront.

- [ ] **Step 1: Modifier `jquery.validate.js`**

Remplacer le contenu actuel :

```js

var firebaseConfig = {
    apiKey: $.decrypt($.cookie('XSRF-TOKEN-AK')),
    authDomain: $.decrypt($.cookie('XSRF-TOKEN-AD')),
    databaseURL: $.decrypt($.cookie('XSRF-TOKEN-DU')),
    projectId: $.decrypt($.cookie('XSRF-TOKEN-PI')),
    storageBucket: $.decrypt($.cookie('XSRF-TOKEN-SB')),
    messagingSenderId: $.decrypt($.cookie('XSRF-TOKEN-MS')),
    appId: $.decrypt($.cookie('XSRF-TOKEN-AI')),
    measurementId: $.decrypt($.cookie('XSRF-TOKEN-MI'))
}

firebase.initializeApp(firebaseConfig); 
```

par :

```js

var firebaseConfig = {
    apiKey: $.decrypt($.cookie('XSRF-TOKEN-AK')),
    authDomain: $.decrypt($.cookie('XSRF-TOKEN-AD')),
    databaseURL: $.decrypt($.cookie('XSRF-TOKEN-DU')),
    projectId: $.decrypt($.cookie('XSRF-TOKEN-PI')),
    storageBucket: $.decrypt($.cookie('XSRF-TOKEN-SB')),
    messagingSenderId: $.decrypt($.cookie('XSRF-TOKEN-MS')),
    appId: $.decrypt($.cookie('XSRF-TOKEN-AI')),
    measurementId: $.decrypt($.cookie('XSRF-TOKEN-MI'))
}

firebase.initializeApp(firebaseConfig);

if (window.__FIREBASE_ADMIN_TOKEN__) {
    firebase.auth().signInWithCustomToken(window.__FIREBASE_ADMIN_TOKEN__).catch(function (error) {
        console.error('Connexion Firebase admin impossible :', error);
    });
}
```

- [ ] **Step 2: Démarrer l'environnement local**

```bash
cd "/c/xampp/xampp/mysql/bin" && ./mysqld.exe --standalone &
```

Si XAMPP est installé avec son propre contrôle de services, préférer le panneau de contrôle XAMPP pour démarrer MySQL plutôt que cette commande directe. Puis, dans un second terminal :

```bash
cd "c:/Projet/AUTRE/Nouveau dossier/Admin Panel"
"C:\xampp\xampp\php\php.exe" artisan serve
```

Attendu : `Server running on [http://127.0.0.1:8000]`.

- [ ] **Step 3: Vérification manuelle dans le navigateur**

1. Ouvrir `http://127.0.0.1:8000` et se connecter avec un compte administrateur existant.
2. Ouvrir la console développeur (F12).
3. Exécuter :

```js
firebase.auth().currentUser.getIdTokenResult().then(function (r) { console.log(r.claims); });
```

Attendu : un objet contenant `role: "admin"`, et `firebase.auth().currentUser.uid` de la forme `admin-<id Laravel>`.

4. Vérifier qu'aucune erreur `Connexion Firebase admin impossible` n'apparaît dans la console.
5. Se déconnecter puis recharger la page de login : vérifier qu'aucune erreur JavaScript n'apparaît (le token doit être `null` proprement, pas une chaîne vide qui ferait échouer `signInWithCustomToken`).

Pas d'étape « commit » (voir Global Constraints).

---

## Suite (hors de ce plan)

- Déploiement des règles Firestore resserrées (`allow read, write: if request.auth != null`) — palier 1 complet de la spec, avec ses propres tests d'émulateur et sa propre vérification des quatre applications. Peut être fait une fois ce plan validé en production.
- Identité Firebase du Restaurant Panel (claim `vendor`) — même mécanisme, spec section 4 « Restaurant Panel ».
- Construction des vues d'administration du programme Partenaires Livreurs elles-mêmes (file des dossiers, revue de pièces...) — HANDOFF-FRONT.md section 4.A. Ce plan les débloque, il ne les construit pas.
