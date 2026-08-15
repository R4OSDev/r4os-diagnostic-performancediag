PERFDIAG.R4X
==============

PERFDIAG prueft den aktuellen R4DEV-Performancevertrag und fachliche
Subsystemwerte:

- Scheduler, Preemption, Wait-/Queue-Latenzen und SIMD-State
- Driver-Workqueue und Storage-Completions
- Memory-Pressure, Reclaim, Backing Store und Page-I/O
- Audio-Latenz und Streamfortschritt
- Loader-/R4P-Lifecycle und Hot-Path-Indizes
- Loader-Dateipuffer und Speichergrenzen

Die Ausgabe besteht aus aktuellen Snapshots und expliziten Result-Markern.
Benoetigte optionale Felder werden mit hasFn geprueft.
