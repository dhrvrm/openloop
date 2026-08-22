import { useRef, useState, type PointerEvent } from "react";
import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import {
  ArrowDown,
  ArrowRight,
  BracketsAngle,
  GithubLogo,
  List,
  Microphone,
  Waveform,
  X,
} from "@phosphor-icons/react";

gsap.registerPlugin(ScrollTrigger, useGSAP);

const repository = "https://github.com/dhrvrm/openloop";
const version = "1.0.3";
const download = `${repository}/releases/download/v${version}/OpenLoop-${version}-arm64.dmg`;
const checksum = "c556d51e2f58099e9acd9d2d1a1e09555f04a2aabd54d565cbdaad0237d55444";

const nodes = [
  { label: "Project", x: 13, y: 39, tone: "quiet" },
  { label: "Observation", x: 34, y: 17, tone: "quiet" },
  { label: "Decision", x: 47, y: 49, tone: "active" },
  { label: "Question", x: 69, y: 23, tone: "quiet" },
  { label: "Person", x: 35, y: 76, tone: "quiet" },
  { label: "Evidence", x: 67, y: 67, tone: "evidence" },
];

const edges = [[0, 1], [0, 2], [1, 2], [1, 3], [2, 3], [2, 4], [2, 5], [3, 5], [4, 5]];

function Logo() {
  return (
    <a className="logo" href="#top" aria-label="OpenLoop home">
      <span className="logo-mark"><span /></span>
      <span>OpenLoop</span>
    </a>
  );
}

function ActionLink({ href, kind = "primary", children }: {
  href: string;
  kind?: "primary" | "secondary";
  children: React.ReactNode;
}) {
  return <a className={`action action--${kind}`} href={href}>{children}<ArrowRight weight="bold" /></a>;
}

function ProductFrame({ className = "", crop = false }: { className?: string; crop?: boolean }) {
  return (
    <div className={`product-frame ${className}`}>
      <div className="frame-bar"><i /><i /><i /><span>OpenLoop ADHD</span></div>
      <div className={`product-demo${crop ? " product-demo--crop" : ""}`} role="img" aria-label="OpenLoop interface illustration showing task lists and local voice capture">
        <aside className="demo-sidebar">
          <b><span className="demo-logo" />OpenLoop</b>
          {[["Now", "4"], ["Upcoming", ""], ["Someday", ""], ["Inbox", "2"], ["Transcripts", "3"]].map(([label, count], index) => (
            <span className={index === 0 ? "is-current" : ""} key={label}><i />{label}<small>{count}</small></span>
          ))}
        </aside>
        <div className="demo-content">
          <small>FOCUS</small>
          <h3>Now</h3>
          <p>One useful next step. Everything else stays safe.</p>
          <div className="demo-capture"><span>What should OpenLoop hold for you?</span><b>Record</b></div>
          <div className="demo-task"><i /><div><b>Release reliability</b><span>Compare the saved audio and final transcript</span></div></div>
          <div className="demo-task"><i /><div><b>Voice product</b><span>Review the Hindi and English terminology</span></div></div>
        </div>
        <aside className="demo-inspector">
          <small>LOCAL SYSTEM</small>
          <b><i /> Listening</b>
          <AudioMeter />
          <dl><div><dt>Language</dt><dd>Auto</dd></div><div><dt>Model</dt><dd>Local</dd></div><div><dt>Storage</dt><dd>Encrypted</dd></div></dl>
        </aside>
      </div>
    </div>
  );
}

function AudioMeter() {
  const bars = [18, 32, 58, 76, 43, 88, 62, 38, 71, 93, 54, 31, 65, 47, 25, 56, 34, 19];
  return <div className="audio-meter" aria-label="Live microphone input">
    {bars.map((height, index) => <i key={index} style={{ "--meter": `${height}%`, "--delay": `${index * -43}ms` } as React.CSSProperties} />)}
  </div>;
}

function App() {
  const root = useRef<HTMLDivElement>(null);
  const heroObject = useRef<HTMLDivElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);

  useGSAP(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) return;

    gsap.from(".hero-copy > *", {
      y: 34,
      opacity: 0,
      duration: 1.05,
      stagger: 0.09,
      ease: "power3.out",
    });
    gsap.from(".hero-object", {
      y: 90,
      rotateX: 9,
      rotateY: -8,
      opacity: 0,
      duration: 1.35,
      delay: 0.15,
      ease: "power4.out",
    });

    gsap.utils.toArray<HTMLElement>("[data-reveal]").forEach((element) => {
      gsap.from(element, {
        y: 44,
        opacity: 0,
        duration: 0.9,
        ease: "power3.out",
        scrollTrigger: { trigger: element, start: "top 84%", once: true },
      });
    });

    const voiceTimeline = gsap.timeline({
      scrollTrigger: {
        trigger: ".voice-stage",
        start: "top 72%",
        end: "bottom 35%",
        scrub: 0.7,
      },
    });
    voiceTimeline
      .fromTo(".voice-screen--back", { x: -70, y: 30, rotateY: 7 }, { x: -20, y: 0, rotateY: 2 }, 0)
      .fromTo(".voice-screen--front", { x: 100, y: 90, rotateY: -10 }, { x: 0, y: 0, rotateY: -2 }, 0);

    gsap.fromTo(".graph-field", { rotateX: 8, rotateZ: -2 }, {
      rotateX: -3,
      rotateZ: 1,
      ease: "none",
      scrollTrigger: { trigger: ".memory", start: "top bottom", end: "bottom top", scrub: true },
    });

    gsap.from(".pipeline-layer", {
      y: 56,
      opacity: 0,
      stagger: 0.08,
      ease: "power3.out",
      scrollTrigger: { trigger: ".engine-stack", start: "top 76%" },
    });
  }, { scope: root });

  function tiltHero(event: PointerEvent<HTMLDivElement>) {
    if (!heroObject.current || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const bounds = event.currentTarget.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    gsap.to(heroObject.current, { rotateY: x * 4, rotateX: y * -3, duration: 0.7, ease: "power3.out" });
  }

  return <div ref={root} className="site-shell">
    <a className="skip-link" href="#main">Skip to content</a>
    <header className="nav-shell">
      <Logo />
      <nav className={menuOpen ? "is-open" : ""} aria-label="Primary navigation">
        <a href="#product">Product</a>
        <a href="#principles">Principles</a>
        <a href="#download">Download</a>
        <a href={repository}>GitHub</a>
      </nav>
      <button className="nav-menu" type="button" aria-expanded={menuOpen} aria-label="Toggle navigation" onClick={() => setMenuOpen(!menuOpen)}>
        {menuOpen ? <X /> : <List />}
      </button>
      <a className="nav-download" href={download}>Download {version}<ArrowDown /></a>
    </header>

    <main id="main">
      <section id="top" className="hero section-dark" onPointerMove={tiltHero}>
        <div className="grid-lines" aria-hidden="true" />
        <div className="hero-copy">
          <span className="eyebrow"><i /> Local voice + working memory</span>
          <h1>Lose the thread.<br />Not the thought.</h1>
          <p>Dictate into any app, keep the raw evidence, and return to the exact context later. The current release runs its speech and memory pipeline on your Mac.</p>
          <div className="action-row">
            <ActionLink href={download}><ArrowDown /> Download {version} for macOS</ActionLink>
            <ActionLink href={repository} kind="secondary"><BracketsAngle /> Steal the code, legally</ActionLink>
          </div>
          <span className="hero-note">Apple silicon · macOS 15+ · 49.3 MB · MIT licensed</span>
        </div>
        <div ref={heroObject} className="hero-object">
          <ProductFrame />
          <div className="recording-chip"><span /><AudioMeter /><b>−24 dB</b></div>
        </div>
      </section>

      <section id="product" className="voice section-dark">
        <div className="section-heading" data-reveal>
          <span className="section-number">Capture</span>
          <h2>Speak before the thought leaves.</h2>
          <p>Press one shortcut and speak. You can see the sound level and words as they arrive. OpenLoop keeps the original recording with the transcript.</p>
        </div>
        <div className="voice-stage">
          <ProductFrame className="voice-screen voice-screen--back" crop />
          <div className="voice-screen voice-screen--middle recording-panel">
            <div className="recording-state"><span /><b>Recording</b><time>00:00:18</time><em>−14 dB</em></div>
            <AudioMeter />
            <div className="recording-stop" aria-hidden="true"><span /></div>
          </div>
          <div className="voice-screen voice-screen--front partial-panel">
            <div className="partial-tabs"><b>Stable</b><span>Partial</span></div>
            <p>I was thinking that the release time—</p>
            <p lang="hi">वो क्या हम काम कर सकते हैं?</p>
            <p>Can we reduce the release time for SGLC releases<span className="cursor" /> </p>
            <small>English + Hindi · detected locally</small>
          </div>
        </div>
      </section>

      <section className="memory section-dark">
        <div className="memory-copy" data-reveal>
          <span className="section-number">Remember</span>
          <h2>Know why it remembers.</h2>
          <p>OpenLoop keeps decisions, questions, and possible next steps separate. Every saved fact links back to the note or recording it came from.</p>
          <a className="text-link" href={`${repository}#semantic-memory`}>Explore the memory model <ArrowRight /></a>
        </div>
        <div className="graph-field" aria-label="Semantic memory graph visualization">
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
            {edges.map(([a, b], index) => <line key={index} x1={nodes[a].x} y1={nodes[a].y} x2={nodes[b].x} y2={nodes[b].y} />)}
          </svg>
          {nodes.map((node) => <div key={node.label} className={`graph-node graph-node--${node.tone}`} style={{ left: `${node.x}%`, top: `${node.y}%` }}>
            <i /><span>{node.label}</span>
          </div>)}
          <aside className="evidence-card">
            <span>Evidence linked</span>
            <h3>Prefer local quality over silent cloud fallback.</h3>
            <p>Example decision · opens its source</p>
          </aside>
        </div>
      </section>

      <section className="return-section section-light">
        <div className="return-statement" data-reveal>
          <span className="giant-number" aria-hidden="true">03</span>
          <span className="section-number">Return</span>
          <h2>Pick up where you stopped.</h2>
          <p>See what you were doing, the last useful detail, what is still open, and one next step.</p>
        </div>
        <div className="return-window" data-reveal>
          <div className="native-titlebar"><i /><i /><i /><b>OpenLoop</b><span>● Local</span></div>
          <div className="return-content">
            <small>ACTIVE THREAD</small>
            <h3>Release reliability</h3>
            <div className="context-block"><label>LAST CONTEXT</label><p>Hindi and English detection worked, but final accuracy still needs a reliable correction pass.</p></div>
            <div className="context-block"><label>UNRESOLVED</label><p>How should confidence be shown without interrupting dictation?</p></div>
            <a className="return-action" href={`${repository}/blob/main/docs/VOICE_SEMANTIC_OPERATING_LAYER.md`}>Read the evidence model <ArrowRight /></a>
          </div>
        </div>
      </section>

      <section id="principles" className="engine section-dark">
        <div className="engine-copy" data-reveal>
          <span className="section-number">Local engine</span>
          <h2>Your audio stays on your Mac.</h2>
          <p>Recording, transcription, correction, and saved context run locally in this release. The first model download needs a network connection; there is no silent cloud transcription route.</p>
          <dl><div><dt>Execution</dt><dd>On device</dd></div><div><dt>Storage</dt><dd>Encrypted locally</dd></div><div><dt>Network</dt><dd>Explicit, never silent</dd></div></dl>
        </div>
        <div className="engine-stack">
          {[
            ["Microphone", "PCM audio + live level"],
            ["Voice activity", "Speech boundaries"],
            ["Speech models", "Multilingual recognition"],
            ["Local editor", "Terminology + structure"],
            ["Semantic memory", "Evidence + relationships"],
          ].map(([name, detail], index) => <div className="pipeline-layer" key={name} style={{ "--layer": index } as React.CSSProperties}>
            <span>{String(index + 1).padStart(2, "0")}</span><div><b>{name}</b><small>{detail}</small></div><i />
          </div>)}
        </div>
        <aside className="local-note"><i /> Your audio does not leave this Mac in local mode.</aside>
      </section>

      <section className="everywhere section-light">
        <div className="app-rail" data-reveal>
          <div className="dictation-float"><div><span /><b>OpenLoop</b></div><AudioMeter /><p>Use the same context anywhere you work.</p></div>
          {["Browser", "VS Code", "Terminal", "Slack"].map((app, index) => <div key={app} className={`destination destination--${index}`}><span>{app}</span><p>{index === 1 ? "// Same words, code-aware output" : "Same words, correctly formatted."}<i /></p></div>)}
          <div className="output-node"><Waveform weight="bold" /></div>
        </div>
        <div className="everywhere-copy" data-reveal>
          <span className="section-number">Output</span>
          <h2>Speak anywhere<br />you type.</h2>
          <p>OpenLoop puts the result into the current app. It uses the clipboard, macOS accessibility, or keyboard input—whichever works best there.</p>
        </div>
      </section>

      <section className="opensource">
        <div className="opensource-copy" data-reveal>
          <span className="section-number">Open source</span>
          <h2>Take it apart.<br />Make it yours.</h2>
          <ActionLink href={repository} kind="secondary"><GithubLogo weight="fill" /> Steal the code, legally</ActionLink>
          <ul><li>MIT licensed</li><li>Swift 6</li><li>Local-first</li><li>Apple silicon</li></ul>
        </div>
        <div className="machine" data-reveal>
          {["VOICE ENGINE", "SEMANTIC MEMORY", "LOCAL DATA", "OUTPUT ADAPTERS", "POLICY"].map((label, index) => <div key={label} className={`machine-module machine-module--${index}`}><i /><b>{label}</b><span>{index % 2 ? "Evidence · links · recall" : "Ports · adapters · tests"}</span></div>)}
        </div>
      </section>

      <section id="download" className="release-section section-dark">
        <div className="release-copy" data-reveal>
          <span className="section-number">Current build</span>
          <h2>Install the Mac app.</h2>
          <p>OpenLoop {version} is an Apple-silicon community build for macOS 15 or later. It is ad-hoc signed and not Apple-notarized yet.</p>
          <ActionLink href={download}><ArrowDown /> Download the DMG</ActionLink>
        </div>
        <div className="release-ledger" data-reveal>
          <dl>
            <div><dt>Version</dt><dd>{version} (16)</dd></div>
            <div><dt>Download</dt><dd>49.3 MB · arm64</dd></div>
            <div><dt>Requires</dt><dd>macOS 15+ · Apple silicon</dd></div>
            <div><dt>Signing</dt><dd>Ad-hoc community build</dd></div>
            <div><dt>SHA-256</dt><dd><code>{checksum}</code></dd></div>
          </dl>
          <ol>
            <li>Open the DMG and drag OpenLoop ADHD to Applications.</li>
            <li>On first launch, Control-click the app and choose Open.</li>
            <li>Microphone access is requested only when you start recording.</li>
          </ol>
          <a className="checksum-link" href={`${download}.sha256`}>Download checksum <ArrowRight /></a>
        </div>
      </section>

      <section className="closing section-light">
        <div data-reveal>
          <Microphone weight="light" />
          <h2>Keep the thought.</h2>
          <div className="action-row">
            <ActionLink href={download}><ArrowDown /> Download OpenLoop {version}</ActionLink>
            <ActionLink href={repository} kind="secondary"><GithubLogo /> View source</ActionLink>
          </div>
          <p>Open source. Local-first. Built for macOS.</p>
        </div>
        <footer><Logo /><nav><a href={`${repository}/tree/main/docs`}>Documentation</a><a href={`${repository}/releases`}>Releases</a><a href={`${repository}/blob/main/SECURITY.md`}>Security</a><a href={`${import.meta.env.BASE_URL}privacy.html`}>Privacy</a><a href={`${repository}/blob/main/LICENSE`}>License</a></nav></footer>
        <div className="closing-wave"><AudioMeter /></div>
      </section>
    </main>
  </div>;
}

export { App };
