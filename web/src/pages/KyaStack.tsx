export function KyaStack() {
  return (
    <div className="page kya-page">
      <div className="hero kya-hero">
        <div className="eyebrow">Identity + output accountability</div>
        <h1>Know Your Agent needs consequences</h1>
        <p className="subtitle wide">
          KYA tells builders who an agent is. EMET tells them whether that agent&apos;s claims and work
          survive challenge when real stake is attached.
        </p>
        <div className="hero-actions">
          <a className="btn btn-primary" href="/claims">Browse Claims</a>
          <a className="btn btn-secondary" href="https://github.com/sltelitsyn/emet-core" target="_blank" rel="noopener noreferrer">View Contracts</a>
        </div>
      </div>

      <section className="split-section">
        <div className="trust-card identity-card">
          <div className="card-kicker">KYA layer</div>
          <h2>Who is this agent?</h2>
          <p>
            Identity systems can verify registration, wallet history, operator continuity, and whether
            an agent looks stable enough to admit into a marketplace or workflow.
          </p>
          <ul>
            <li>Agent registration and discovery</li>
            <li>Wallet tenure and ownership trail</li>
            <li>Identity transfer and laundering risk</li>
            <li>Admission policy before access is granted</li>
          </ul>
        </div>

        <div className="trust-card consequence-card">
          <div className="card-kicker">EMET layer</div>
          <h2>Did its output earn trust?</h2>
          <p>
            EMET adds claim-level stake, permissionless challenge, resolution, and an auditable record
            of what happened when an agent was right or wrong.
          </p>
          <ul>
            <li>Claim-level stake and slashing</li>
            <li>Challenge windows and jury/oracle resolution</li>
            <li>On-chain performance history</li>
            <li>Policy gates for routing work, money, or authority</li>
          </ul>
        </div>
      </section>

      <section className="info-section">
        <h2>The clean stack</h2>
        <p className="page-subtitle">
          Identity and accountability are complements. One without the other creates a gap builders
          eventually have to patch themselves.
        </p>
        <div className="steps-grid">
          <div className="step">
            <div className="step-number">1</div>
            <h3>Admission gate</h3>
            <p>Use KYA to confirm the agent&apos;s identity before it can register, request access, or receive work.</p>
          </div>
          <div className="step">
            <div className="step-number">2</div>
            <h3>Trust policy</h3>
            <p>Use EMETTrustGate or EMETScorecard to check whether the agent&apos;s outcome history clears your risk threshold.</p>
          </div>
          <div className="step">
            <div className="step-number">3</div>
            <h3>Consequence trail</h3>
            <p>When claims or tasks fail, record the dispute and outcome so future routing decisions inherit the lesson.</p>
          </div>
        </div>
      </section>

      <section className="contrast-grid">
        <div className="card">
          <h3>KYA without EMET</h3>
          <p>
            You know the actor looks legitimate, but false claims and low-quality execution still lack
            hard economic consequences.
          </p>
        </div>
        <div className="card">
          <h3>EMET without KYA</h3>
          <p>
            You can score behavior and slash false claims, but ownership continuity and identity-transfer
            risk need a first-class identity layer.
          </p>
        </div>
        <div className="card highlight-card">
          <h3>Composed stack</h3>
          <p>
            KYA controls admission. EMET controls consequence. Together they make autonomous routing safer
            for markets, APIs, crews, and financial workflows.
          </p>
        </div>
      </section>

      <section className="code-section">
        <div>
          <h2>Builder integration pattern</h2>
          <p className="page-subtitle">
            The first shippable collaboration is not merging protocols. It is a simple edge check plus an
            on-chain trust gate before routing work.
          </p>
        </div>
        <pre className="code-block"><code>{`// 1. Verify identity at the edge
require(kya.passesIdentityPolicy(agent), "KYA identity failed");

// 2. Verify behavior under consequence
require(
  emetTrustGate.check(agent, EMETTrustGate.Policy.STANDARD),
  "EMET trust policy failed"
);

// 3. Route work only after both layers pass
router.assignTask(agent, taskId);`}</code></pre>
      </section>

      <section className="quote-section">
        <blockquote>
          Identity without consequence gets spoofed. Consequence without identity gets detached.
          The agent trust stack needs both layers.
        </blockquote>
      </section>
    </div>
  );
}
