// Codes des événements du journal (tableaux positionnels, préfiguration spec §7.2).
// [typeCode] ou [typeCode, arg] — la séquence est implicite (index dans le journal).
module ScoreEvent {
    const TYPE_POINT_ME = 0;
    const TYPE_POINT_OPPONENT = 1;
    const TYPE_SET_FINISHED = 2;      // [TYPE_SET_FINISHED, winner] winner: 0=moi 1=adversaire
    const TYPE_SET_CHANGED = 3;       // [TYPE_SET_CHANGED, winner] winner: 0/1 crédité, -1 = déjà crédité ou égalité
    const TYPE_MATCH_FINISHED = 4;    // verrou terminal (§4.5 : ne s'annule pas)
}

// Phases dérivées exposées par le moteur.
module ScorePhase {
    const PLAYING = 0;        // set en cours, points comptables
    const SET_RESULT = 1;     // set terminé (auto), en attente « set suivant »
    const MATCH_FINISHED = 2; // match terminé, verrouillé
}
