// Config backend — placeholders committés. scripts/build-release.sh injecte
// les vraies valeurs dans sa copie temporaire au build. On ne passe PAS par
// les defaults settings.xml : Properties.getValue ne les retourne pas sur
// matériel (bug 2, phase 4a) → app silencieuse. Consts compilées = fiables.
module BackendConfig {
    const BACKEND_URL = "";
    const DEVICE_KEY = "";
}
