# RES Suite Kubernetes Wrapper

Guida per la preparazione del repository Git contenente il wrapper 
del chart RES Suite da collegare ad Argo CD.

RES fornisce questo repository come esempio di wrapper Helm. Il wrapper non
modifica il chart ufficiale `ressuite`: lo dichiara come dipendenza, genera le
ConfigMap con i file di configurazione applicativa e passa al chart RES Suite
i riferimenti alle ConfigMap esterne.

Questa guida riguarda solo la preparazione del repository wrapper. La creazione
del namespace, la creazione dei secrets, la configurazione dei values e
l'installazione della suite sono trattate nella guida operativa di
installazione.

## Obiettivo

Al termine della preparazione, il cliente avra' un repository Git contenente:

```text
Chart.yaml
templates/
files/
values.yaml
```

Questo è il repository da collegare ad Argo CD.

Possono essere mantenuti nel repository remoto anche `README.md`, `ressuite-helm-bootstrap.sh` ed 
il file `.env`. Si consiglia quest ultimo di non pusharlo con credenziali valorizzate.

## Contenuto Iniziale

Il repository fornito da RES contiene:

```text
Chart.yaml
README.md
ressuite-helm-bootstrap.sh
templates/
```

- `Chart.yaml`: definisce il wrapper chart e la dipendenza dal chart Helm
  `ressuite`.
- `templates/`: contiene i template Helm che creano le ConfigMap esterne.
- `ressuite-helm-bootstrap.sh`: scarica il chart RES Suite, estrae i file
  standard e genera un template di configurazione.
- `README.md`: contiene questa guida.

Il repository iniziale non contiene `files/` e `values.yaml`: andranno preparati
in fase di bootstrap.

## Prerequisiti

Prima di iniziare verificare di avere:

- un ambiente Linux fornito di comandi `helm` e `tar`;
- puntamenti e credenziali di accesso al repository Helm contenente il chart `ressuite`;
- un repository Git in cui versionare il wrapper e la configurazione.

Il repository Helm puo' essere il Nexus RES, usando le credenziali opportunamente fornite,
oppure un repository Helm privato. In quest ultimo caso,
il chart `ressuite` deve essere gia' stato caricato su quel repository, il quale
deve essere correttamente puntato dalla dipendenza nel file `Chart.yaml`.

## Flusso Di Lavoro

La guida distingue due scenari:

- prima installazione: il repository non contiene ancora `files/` e
  `values.yaml`;
- aggiornamento: il repository cliente contiene gia' una configurazione e deve
  essere allineato a una nuova versione del chart RES Suite.

In entrambi i casi lo script scarica il chart dichiarato in `Chart.yaml` e
genera una base di lavoro locale:

```text
config/
values-template.yaml
```

Gli output generati non devono essere committati direttamente. In prima
installazione vengono rinominati e personalizzati. In aggiornamento devono essere
usati per una diff rispetto alla configurazione pre esistente.

## Configurazione Del Repository Helm

Verificare quale repository Helm usare:

- Nexus RES, qualora l'ambiente possa scaricare il chart dal repository RES;
- repository Helm privato, se per vincoli di sicurezza o rete il chart debba
  essere copiato in un repository interno.

Se si usa un repository diverso da quello RES, modificare la dipendenza in
`Chart.yaml`:

```yaml
dependencies:
  - name: ressuite
    version: <ressuite-chart-version>
    repository: <repository-helm>
```

La versione da indicare deve essere scelta (ed eventualmente pre-caricata nel repo helm privato)
in precedenza.

Compilare il file `.env` con le credenziali del repository Helm scelto:

```sh
HELM_REPO_NAME=ressuite-helm-nexus
HELM_REPO_URL=https://nexus.aws.res-it.com/repository/helm/
HELM_REPO_USERNAME=<utente>
HELM_REPO_PASSWORD=<password>
```

Il file `.env` verrà usato solo dallo script di bootstrap. Non committare
credenziali reali.

## Prima Installazione

Eseguire questi passaggi dalla root del wrapper.

1. Eseguire lo script.

   ```sh
   ./ressuite-helm-bootstrap.sh
   ```

   Lo script verifica i prerequisiti, carica il `.env`, registra il repository
   Helm, scarica la dipendenza `ressuite`, estrae i file standard in `config/`
   e genera `values-template.yaml`.

2. Rinominare `config/` in `files/`.

   ```sh
   mv config files
   ```

3. Personalizzare il contenuto di `files/`.

   La struttura delle cartelle deve rimanere invariata. I file appena generati sono
   una base di partenza e devono essere adattati all'ambiente secondo
   quanto previsto dalla guida operativa, in particolar modo i file di connessione.

4. Rinominare `values-template.yaml` in `values.yaml`.

   ```sh
   mv values-template.yaml values.yaml
   ```

5. Personalizzare `values.yaml`.

   Tutta la configurazione del chart RES Suite deve rimanere sotto la chiave
   `ressuite:`, poiché `ressuite` è una dipendenza del wrapper chart. I valori
   da compilare sono descritti nella guida operativa di installazione.

Il risultato atteso è un repository cliente con `Chart.yaml`, `templates/`,
`files/` e `values.yaml`, pronto per essere collegato ad Argo CD dopo aver
preparato namespace e Secret come indicato nella guida operativa.

## Aggiornamento

Per aggiornare una configurazione gia' esistente, seguire lo stesso principio
della prima installazione, ma senza rinominare o sostituire subito gli output
generati.

1. Aggiornare la dipendenza in `Chart.yaml`.

   ```yaml
   dependencies:
     - name: ressuite
       version: <nuova-versione>
       repository: <repository-helm>
   ```

2. Eseguire lo script.

   ```sh
   ./ressuite-helm-bootstrap.sh
   ```

   Lo script rigenera `config/` e `values-template.yaml` a partire dalla nuova
   versione del chart.

3. Confrontare `config/` con `files/`.

   Usare strumenti di diff a scelta, ad esempio `diff`, `meld`, `vimdiff`, un
   IDE o un sistema di merge. Lo scopo è capire quali file standard sono stati
   aggiunti, modificati o rimossi nella nuova versione.

4. Aggiornare `files/`.

   Riportare solo le modifiche necessarie, mantenendo le personalizzazioni
   cliente e la struttura delle cartelle. Non sostituire in blocco `files/` se
   contiene configurazioni gia' personalizzate.

5. Confrontare `values-template.yaml` con `values.yaml`.

   Il confronto serve a identificare nuove chiavi, chiavi rimosse o default
   cambiati nella nuova versione del chart.

6. Aggiornare `values.yaml`.

   Riportare solo le modifiche richieste dalla nuova versione, mantenendo i
   valori specifici dell'ambiente cliente.

7. Eliminare file temporanei.

   `config/` e  `values-template.yaml` non fanno parte
   del repository finale da collegare ad Argo CD.

## Opzioni Dello Script

Opzioni disponibili:

```sh
./ressuite-helm-bootstrap.sh --debug
./ressuite-helm-bootstrap.sh --quiet
./ressuite-helm-bootstrap.sh --help
```

Lo script elimina e rigenera `config/` e `values-template.yaml`
dopo conferma interattiva. In modalita' `--quiet`, se questi output esistono
gia', lo script si interrompe.

## Struttura Di files/

Dopo la prima preparazione, il wrapper deve contenere la cartella `files/`.
Questa cartella deriva da `config/` e contiene i file di configurazione
applicativa del cliente.

La struttura attesa dal wrapper è:

```text
files/
  wicplanet/
    internal-config/
      db/
      etc/
      logs/
      search/
  batchwatch/
    internal-config/
      db/
      logs/
      search/
      templateExcel/
  ds-watch/
    internal-config/
      db/
      logs/
      search/
      templateExcel/
```

I template Helm leggono i file tramite `.Files.Glob "files/..."`. Se la
cartella `files/` non esiste o non rispetta la struttura prevista, le ConfigMap
generate saranno incomplete.

## ConfigMap Generate Dal Wrapper

Con `ressuite.configSource.mode=external`, il chart RES Suite monta ConfigMap
esterne invece di generare direttamente i bundle file-backed.

Questo wrapper crea le ConfigMap esterne per i componenti gestiti dai template
presenti nella cartella `templates/`:

- `wicplanet-be`;
- `batch-watch-be`;
- `ds-watch-be`.

I riferimenti alle ConfigMap esterne sono generati nel `values-template.yaml`
scaricato dallo script e devono rimanere coerenti in `values.yaml`.

Le ConfigMap vengono create solo se il relativo componente è abilitato nei
valori del chart.

## Validazione Locale

Dopo aver preparato `files/` e `values.yaml`, validare il rendering prima di
committare la configurazione:

```sh
helm lint . -f values.yaml
helm template test . -f values.yaml
helm template test . -f values.yaml > rendered.yaml
```

Il file `rendered.yaml` è un output locale di verifica e non deve essere
committato.

## Cosa Versionare

Versionare:

```text
charts/                       # required, contiene il chart specificato come dipendenza
Chart.yaml                    # required per helm
README.md                     # opzionale, meglio se versionato con il wrapper
ressuite-helm-bootstrap.sh    # opzionale, meglio se versionato con il wrapper
templates/                    # required, contiene le configMap dei files di configurazione della suite
files/                        # required, contiene i files di configurazione della suite
values.yaml                   # required, contiene i values necessari al funzionamento
```

Non versionare:

```text
.env con credenziali reali
config/
Chart.lock
rendered*.yaml
values-template.yaml
*.tgz
file contenenti password, token, chiavi o Secret reali
```