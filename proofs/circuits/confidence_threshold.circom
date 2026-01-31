pragma circom 2.1.0;

/*
 * ConfidenceThreshold — Prove confidence > threshold without revealing exact value
 *
 * Public inputs:  threshold (minimum required confidence, scaled ×10000)
 * Private inputs: confidence (actual confidence value, scaled ×10000)
 *
 * The prover demonstrates their claim confidence exceeds a threshold
 * without revealing the precise confidence score.
 *
 * Values are integers scaled by 10000 (e.g., 0.85 → 8500, 0.95 → 9500).
 * Use the confidenceToSignal() helper in zkp.js for conversion.
 *
 * EMET use cases:
 * - "My claim confidence is above 90%" without revealing it's exactly 94.3%
 * - Threshold-gated access to claim networks
 * - Minimum-confidence requirements for aggregation
 */

include "../node_modules/circomlib/circuits/comparators.circom";

template ConfidenceThreshold() {
    // --- Signals ---
    signal input confidence;    // Private: actual confidence (0-10000)
    signal input threshold;     // Public:  minimum required confidence (0-10000)

    // --- Range checks ---
    // Ensure confidence is in valid range [0, 10000].
    // We use LessThan with 14 bits (covers 0..16383, sufficient for 0..10000).
    component upperBound = LessThan(14);
    upperBound.in[0] <== confidence;
    upperBound.in[1] <== 10001;
    upperBound.out === 1;

    // Ensure threshold is in valid range [0, 10000].
    component thresholdBound = LessThan(14);
    thresholdBound.in[0] <== threshold;
    thresholdBound.in[1] <== 10001;
    thresholdBound.out === 1;

    // --- Core constraint ---
    // Prove: confidence >= threshold
    // Equivalent to: threshold <= confidence
    // Using GreaterEqThan: out = 1 if in[0] >= in[1]
    component gte = GreaterEqThan(14);
    gte.in[0] <== confidence;
    gte.in[1] <== threshold;

    // Constraint: the comparison MUST hold (output must be 1)
    gte.out === 1;
}

component main { public [threshold] } = ConfidenceThreshold();
