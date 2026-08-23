import { useEffect, useRef, useState, type PointerEvent } from "react";
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
  Moon,
  Sun,
  Waveform,
  X,
} from "@phosphor-icons/react";

gsap.registerPlugin(ScrollTrigger, useGSAP);

const repository = "https://github.com/dhrvrm/openloop";
const version = "1.0.6";
const download = `${repository}/releases/download/v${version}/OpenLoop-${version}-arm64.dmg`;
const checksum = "c14c58bc1079c7bd43b60d5aadfa3bc2a7daae9b197a2ab195837531287ae461";

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
      <div className={`product-demo${crop ? " product-demo--crop" : ""}`} role="img" aria-label="OpenLoop interface illustration showing an open task list and bottom voice capture bar">
        <aside className="demo-sidebar">
          <b><span className="demo-logo" /><span>OpenLoop<small>Private working memory</small></span></b>
          {[["Now", "4"], ["Upcoming", ""], ["Someday", ""], ["Inbox", "2"], ["Transcripts", "3"]].map(([label, count], index) => (
            <span className={index === 0 ? "is-current" : ""} key={label}><i />{label}<small>{count}</small></span>
          ))}
        </aside>
        <div className="demo-workspace">
          <div className="demo-toolbar"><span>☰</span><b>Now</b><em>⌃⌥R · Recording started</em><span>◐</span><span>☷</span></div>
          <div className="demo-content">
            <h3><i>★</i>Now</h3>
            <p>Pick one useful next step. Everything else stays safe.</p>
            <div className="demo-task"><i /><div><b>Visitor research</b><span>Send the revised interview guide to Maya</span></div></div>
            <div className="demo-task"><i /><div><b>Prototype review</b><span>Test the shorter museum-guide introduction</span></div></div>
          </div>
          <div className="demo-capture"><span>＋</span><p>Capture a thought…</p><b>●&nbsp; Record</b><i>≋</i><i>•••</i></div>
        </div>
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

function AlgorithmicField() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const context = canvas.getContext("2d");
    if (!context) return;
    const surface: HTMLCanvasElement = canvas;
    const drawing: CanvasRenderingContext2D = context;

    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let animation = 0;
    let width = 0;
    let height = 0;
    let scale = 1;

    function seededRandom(seed: number) {
      let value = seed >>> 0;
      return () => {
        value = (value * 1664525 + 1013904223) >>> 0;
        return value / 4294967296;
      };
    }

    function resize() {
      const bounds = surface.getBoundingClientRect();
      scale = Math.min(window.devicePixelRatio || 1, 2);
      width = bounds.width;
      height = bounds.height;
      surface.width = Math.round(width * scale);
      surface.height = Math.round(height * scale);
      drawing.setTransform(scale, 0, 0, scale, 0, 0);
    }

    function draw(time = 0) {
      drawing.clearRect(0, 0, width, height);
      const random = seededRandom(74291);
      const drift = reduceMotion ? 0 : Math.sin(time * 0.00018) * 0.22;
      const originX = width * 0.68;
      const originY = height * 0.46;

      for (let line = 0; line < 68; line += 1) {
        let x = originX + (random() - 0.5) * width * 0.58;
        let y = originY + (random() - 0.5) * height * 0.72;
        drawing.beginPath();
        drawing.moveTo(x, y);
        for (let step = 0; step < 34; step += 1) {
          const dx = (x - originX) / Math.max(width, 1);
          const dy = (y - originY) / Math.max(height, 1);
          const angle = Math.atan2(dy, dx) + Math.PI / 2 + Math.sin(dx * 9 + dy * 7) * 0.85 + drift;
          x += Math.cos(angle) * 9.5;
          y += Math.sin(angle) * 9.5;
          drawing.lineTo(x, y);
        }
        const blue = line % 7 !== 0;
        drawing.strokeStyle = blue ? "rgba(73, 106, 157, 0.16)" : "rgba(230, 79, 70, 0.13)";
        drawing.lineWidth = blue ? 0.8 : 1.15;
        drawing.stroke();
      }

      if (!reduceMotion) {
        animation = window.requestAnimationFrame(draw);
      }
    }

    resize();
    draw();
    window.addEventListener("resize", resize);
    return () => {
      window.removeEventListener("resize", resize);
      window.cancelAnimationFrame(animation);
    };
  }, []);

  return <canvas ref={canvasRef} className="algorithmic-field" aria-hidden="true" />;
}

function App() {
  const root = useRef<HTMLDivElement>(null);
  const heroObject = useRef<HTMLDivElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [theme, setTheme] = useState<"light" | "dark">(() => {
    const requested = new URLSearchParams(window.location.search).get("theme");
    if (requested === "light" || requested === "dark") return requested;
    const saved = window.localStorage.getItem("openloop-site-theme");
    if (saved === "light" || saved === "dark") return saved;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  });

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
    window.localStorage.setItem("openloop-site-theme", theme);
  }, [theme]);

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
      <div className="nav-actions">
        <button
          className="theme-toggle"
          type="button"
          aria-label={`Use ${theme === "light" ? "dark" : "light"} theme`}
          onClick={() => setTheme(theme === "light" ? "dark" : "light")}
        >
          {theme === "light" ? <Moon /> : <Sun />}
        </button>
        <a className="nav-download" href={download}>Download {version}<ArrowDown /></a>
      </div>
    </header>

    <main id="main">
      <section id="top" className="hero section-light" onPointerMove={tiltHero}>
        <div className="grid-lines" aria-hidden="true" />
        <AlgorithmicField />
        <div className="hero-copy">
          <span className="eyebrow"><i /> Voice, context, and memory on your Mac</span>
          <h1><span>Speak freely.</span><span>Keep the thread.</span></h1>
          <p>Dictate into the app you are using. OpenLoop keeps the recording, transcript, and useful context together so you can return without reconstructing the thought.</p>
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
            <p>The exhibition guide should feel useful before it feels clever.</p>
            <p lang="hi">अब onboarding को तीन छोटे steps में रखते हैं।</p>
            <p>Then we can test it with five first-time visitors<span className="cursor" /> </p>
            <small>English + Hindi · detected automatically</small>
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
            <h3>Museum guide launch</h3>
            <div className="context-block"><label>LAST CONTEXT</label><p>The first visit test showed that people found the map quickly but skipped the audio introduction.</p></div>
            <div className="context-block"><label>UNRESOLVED</label><p>Should the introduction begin automatically or wait for a tap?</p></div>
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
          <div className="dictation-float"><div><span /><b>OpenLoop</b></div><AudioMeter /><p>Turn the signup check into a reusable validation function.</p></div>
          {["Browser", "VS Code", "Terminal", "Slack"].map((app, index) => <div key={app} className={`destination destination--${index}`}><span>{app}</span><p>{index === 1 ? "// Extract signup validation into a reusable function" : index === 2 ? "npm test -- signup-validation" : index === 3 ? "I split the signup check into a reusable function." : "Draft the validation note for the team."}<i /></p></div>)}
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
            <div><dt>Version</dt><dd>{version} (19)</dd></div>
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
