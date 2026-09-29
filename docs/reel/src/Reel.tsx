import React from "react";
import {
  AbsoluteFill, Easing, OffthreadVideo, Sequence, interpolate, spring, staticFile, useCurrentFrame,
} from "remotion";

export const FPS = 60;
const W = 1920, H = 1080, FW = 1920, FH = 1246; // stage, footage
const f = (s: number) => Math.round(s * FPS);
const FONT = '-apple-system, "SF Pro Display", "Helvetica Neue", sans-serif';

// ---------------------------------------------------------------- the plan
// Times are seconds into the take, as record.sh prints them in out/marks.txt.

type Cam = { t: number; x: number; y: number; s: number; rx?: number; ry?: number; card?: number };
type Cap =
  | { kind: "keys"; t: number; d: number; keys: string[]; text: string }
  | { kind: "feature"; t: number; d: number; title: string; text: string; accent: string }
  | { kind: "chapter"; t: number; d: number; text: string }
  | { kind: "theme"; t: number; d: number; name: string; color: string };
type Seg = { src: [number, number]; rate: number; cams: Cam[]; caps: Cap[] };

const CARD = { x: FW / 2, y: FH / 2, s: 0.8, card: 1 };
const FULL = { x: FW / 2, y: H / 2, s: 1, card: 0 };

// Push in on a popup and keep it on the right third, with room for a headline on the left.
function onPopup(r: [number, number, number, number]): Omit<Cam, "t"> {
  const [x0, y0, x1, y1] = r;
  const s = Math.min(2.1, (H * 0.84) / (y1 - y0));
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  const x = cx - (1430 - W / 2) / s;
  const y = Math.max(H / 2 / s, Math.min(FH - H / 2 / s, cy));
  return { x, y, s, card: 0 };
}

const popups: { t: number; r: [number, number, number, number]; title: string; text: string; accent: string }[] = [
  { t: 20.08, r: [1506, 30, 1892, 560], title: "Your day, one click away.", text: "Today's events and the month, right from the clock.", accent: "#ff6b6b" },
  { t: 23.84, r: [1314, 30, 1698, 846], title: "Weather, on the bar.", text: "The next hours and three days ahead, where you are.", accent: "#4dabf7" },
  { t: 27.59, r: [1374, 30, 1720, 808], title: "Battery. Wi-Fi. Hotspot.", text: "Join a network or your iPhone's hotspot in one click.", accent: "#51cf66" },
  { t: 31.55, r: [1554, 22, 1914, 540], title: "Catch the runaway app.", text: "CPU, memory and the busiest apps, live.", accent: "#fcc419" },
  { t: 35.31, r: [1202, 42, 1576, 774], title: "Never hit your AI limit by surprise.", text: "Claude, Codex and Copilot plan usage, side by side.", accent: "#ff922b" },
  { t: 39.48, r: [1198, 36, 1624, 924], title: "Stay on top of your PRs.", text: "Reviews, checks and conflicts at a glance.", accent: "#cc5de8" },
];

const themes = [
  { t: 44.9, name: "Catppuccin", color: "#cba6f7" },
  { t: 48.19, name: "Gruvbox", color: "#fabd2f" },
  { t: 51.42, name: "Osaka Jade", color: "#5cf5c8" },
  { t: 54.71, name: "Tokyo Night", color: "#7aa2f7" },
  { t: 57.93, name: "Catppuccin Latte", color: "#8839ef" },
];
const THEME_SRC: [number, number] = [43.8, 60.8], THEME_RATE = 1.45;

const segs: Seg[] = [
  {
    src: [1.9, 7.9], rate: 1.25,
    cams: [{ t: 0, ...CARD, s: 0.74, rx: 10, ry: -14 }, { t: 1.6, ...CARD }, { t: 4.8, ...CARD, s: 0.84 }],
    caps: [
      { kind: "chapter", t: 0, d: 1.1, text: "Tile." },
      { kind: "keys", t: 1.0, d: 3.7, keys: ["Super", "Return"], text: "New terminal, tiled for you" },
    ],
  },
  {
    src: [7.8, 11.6], rate: 1,
    cams: [{ t: 0, ...FULL, s: 1.08 }, { t: 3.8, ...FULL, s: 1.0 }],
    caps: [
      { kind: "keys", t: 0.1, d: 1.75, keys: ["Super", "← →"], text: "Scroll the columns" },
      { kind: "keys", t: 1.9, d: 1.85, keys: ["⌥", "."], text: "Resize a column" },
    ],
  },
  {
    src: [11.5, 15.9], rate: 1.2,
    cams: [{ t: 0, ...CARD, s: 0.86, ry: 8 }, { t: 3.67, ...CARD, s: 0.8, ry: -8 }],
    caps: [{ kind: "keys", t: 0.1, d: 3.5, keys: ["Super", "1 – 9"], text: "Nine workspaces" }],
  },
  {
    src: [15.9, 19.9], rate: 1,
    cams: [{ t: 0, ...CARD, s: 0.78 }, { t: 4, ...FULL, s: 1.02 }],
    caps: [{ kind: "keys", t: 0.2, d: 3.7, keys: ["Super", "O"], text: "Every workspace at once" }],
  },
  ...popups.map((p, i): Seg => ({
    src: [p.t - 0.05, p.t + 3.0], rate: 1,
    cams: [{ t: 0, ...FULL, s: 1.05 }, { t: 0.55, ...onPopup(p.r) }, { t: 3.05, ...onPopup(p.r), s: onPopup(p.r).s * 1.04 }],
    caps: [
      ...(i === 0 ? [{ kind: "chapter" as const, t: 0, d: 0.95, text: "Glance." }] : []),
      { kind: "feature", t: i === 0 ? 0.8 : 0.3, d: i === 0 ? 2.2 : 2.7, title: p.title, text: p.text, accent: p.accent },
    ],
  })),
  {
    src: THEME_SRC, rate: THEME_RATE,
    cams: themes.flatMap((th, i) => {
      const t = (th.t - THEME_SRC[0]) / THEME_RATE;
      return [{ t: t - 0.02, ...CARD, s: 0.8, ry: i % 2 ? 7 : -7 }, { t: t + 0.12, ...CARD, s: 0.86, ry: i % 2 ? 5 : -5 }];
    }).concat([{ t: 11.8, ...CARD, s: 0.8, ry: 0 }]).map((c, i, a) => (i === 0 ? { ...c, t: 0 } : c)),
    caps: [
      { kind: "chapter", t: 0, d: 0.85, text: "Make it yours." },
      ...themes.map((th, i): Cap => {
        const t = (th.t - THEME_SRC[0]) / THEME_RATE;
        const next = i + 1 < themes.length ? (themes[i + 1].t - THEME_SRC[0]) / THEME_RATE : t + 2.5;
        return { kind: "theme", t, d: next - t - 0.05, name: th.name, color: th.color };
      }),
    ],
  },
  {
    src: [62.0, 65.6], rate: 1,
    cams: [{ t: 0, ...FULL }, { t: 3.6, ...FULL, s: 1.12, y: 600 }],
    caps: [{ kind: "keys", t: 0.2, d: 3.3, keys: ["Super", "K"], text: "Every shortcut, one key" }],
  },
  {
    src: [66.4, 69.0], rate: 1,
    cams: [{ t: 0, ...CARD, s: 0.82 }, { t: 2.6, ...CARD, s: 0.88 }],
    caps: [{ kind: "keys", t: 0.1, d: 2.45, keys: ["⌥", "`"], text: "Drop-down terminal" }],
  },
];

const INTRO = 3.0, OUTRO = 4.2;
const segLen = (s: Seg) => (s.src[1] - s.src[0]) / s.rate;
const starts: number[] = [];
{
  let t = INTRO;
  for (const s of segs) { starts.push(t); t += segLen(s); }
}
export const totalFrames = f(INTRO + segs.reduce((a, s) => a + segLen(s), 0) + OUTRO);

// ---------------------------------------------------------------- helpers

const ease = Easing.bezier(0.65, 0, 0.35, 1);
function camAt(cams: Cam[], t: number): Required<Cam> {
  const full = (c: Cam): Required<Cam> => ({ rx: 0, ry: 0, card: 0, ...c });
  if (t <= cams[0].t) return full(cams[0]);
  for (let i = 0; i < cams.length - 1; i++) {
    const a = full(cams[i]), b = full(cams[i + 1]);
    if (t <= b.t) {
      const k = ease((t - a.t) / Math.max(0.001, b.t - a.t));
      const mix = (p: number, q: number) => p + (q - p) * k;
      return { t, x: mix(a.x, b.x), y: mix(a.y, b.y), s: mix(a.s, b.s), rx: mix(a.rx, b.rx), ry: mix(a.ry, b.ry), card: mix(a.card, b.card) };
    }
  }
  return full(cams[cams.length - 1]);
}

const Backdrop: React.FC = () => {
  const fr = useCurrentFrame();
  const blob = (color: string, x: number, y: number, r: number, sp: number) => (
    <div style={{
      position: "absolute", width: r, height: r, borderRadius: "50%", background: color, filter: "blur(140px)", opacity: 0.55,
      left: x + Math.sin(fr / (90 * sp)) * 180 - r / 2, top: y + Math.cos(fr / (110 * sp)) * 140 - r / 2,
    }} />
  );
  return (
    <AbsoluteFill style={{ background: "#07070f", overflow: "hidden" }}>
      {blob("#7c3aed", 380, 260, 900, 1)}
      {blob("#db2777", 1560, 820, 800, 1.3)}
      {blob("#0891b2", 1300, 120, 700, 0.8)}
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- footage

const Footage: React.FC<{ seg: Seg }> = ({ seg }) => {
  const fr = useCurrentFrame();
  const t = fr / FPS;
  const c = camAt(seg.cams, t);
  // Each cut lands with a short punch: zoom and blur settle over a few frames.
  const punch = interpolate(fr, [0, 12], [1, 0], { extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
  const s = c.s * (1 + 0.06 * punch);
  return (
    <AbsoluteFill style={{ perspective: 2600 }}>
      <AbsoluteFill style={{ transform: `rotateX(${c.rx}deg) rotateY(${c.ry}deg)`, filter: `blur(${punch * 10}px)` }}>
        <div style={{
          position: "absolute", width: FW, height: FH, transformOrigin: "0 0",
          transform: `translate(${W / 2 - c.x * s}px, ${H / 2 - c.y * s}px) scale(${s})`,
          borderRadius: 30 * c.card / s, overflow: "hidden",
          boxShadow: `0 ${60 * c.card}px ${160 * c.card}px rgba(0,0,0,${0.7 * c.card}), 0 0 0 ${2 * c.card / s}px rgba(255,255,255,${0.18 * c.card})`,
        }}>
          <OffthreadVideo src={staticFile("take.mp4")} muted playbackRate={seg.rate}
            trimBefore={f(seg.src[0])} trimAfter={f(seg.src[1]) + 2} style={{ width: FW, height: FH }} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- captions

const out = (fr: number, d: number, n = 12) =>
  interpolate(fr, [f(d) - n, f(d)], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

const Keycap: React.FC<{ k: string; delay: number }> = ({ k, delay }) => {
  const fr = useCurrentFrame();
  const sp = spring({ frame: fr - delay, fps: FPS, config: { damping: 11, stiffness: 180 } });
  return (
    <div style={{
      minWidth: 92, height: 92, padding: "0 26px", borderRadius: 20, display: "flex", alignItems: "center", justifyContent: "center",
      background: "linear-gradient(#ffffff, #e4e4ee)", borderBottom: "7px solid #a9a9bd", boxSizing: "border-box",
      boxShadow: "0 14px 30px rgba(0,0,0,0.45)", fontSize: k === "`" ? 64 : 42, fontWeight: 700, color: "#15151f",
      transform: `translateY(${(1 - sp) * 40}px) scale(${0.5 + 0.5 * sp})`, opacity: Math.min(1, sp * 1.5),
    }}>{k}</div>
  );
};

const Keys: React.FC<{ cap: Extract<Cap, { kind: "keys" }> }> = ({ cap }) => {
  const fr = useCurrentFrame();
  const o = out(fr, cap.d);
  const tx = spring({ frame: fr - 10, fps: FPS, config: { damping: 16 } });
  const pop = spring({ frame: fr, fps: FPS, config: { damping: 14, stiffness: 200 } });
  return (
    <AbsoluteFill style={{
      justifyContent: "flex-end", alignItems: "center", paddingBottom: 64, opacity: o * Math.min(1, pop * 2),
      transform: `translateY(${(1 - o) * 30 + (1 - pop) * 60}px) scale(${0.85 + 0.15 * pop})`,
    }}>
      <div style={{
        display: "flex", alignItems: "center", gap: 18, padding: "22px 40px 22px 26px", borderRadius: 999,
        background: "rgba(14,14,24,0.72)", backdropFilter: "blur(24px)", border: "1.5px solid rgba(255,255,255,0.16)",
        boxShadow: "0 30px 80px rgba(0,0,0,0.5)",
      }}>
        {cap.keys.map((k, i) => (
          <React.Fragment key={i}>
            {i > 0 && <div style={{ fontSize: 44, fontWeight: 700, color: "rgba(255,255,255,0.7)", opacity: tx }}>+</div>}
            <Keycap k={k} delay={i * 5} />
          </React.Fragment>
        ))}
        <div style={{
          marginLeft: 16, fontSize: 50, fontWeight: 800, color: "white", letterSpacing: -0.5,
          opacity: tx, transform: `translateX(${(1 - tx) * 40}px)`,
        }}>{cap.text}</div>
      </div>
    </AbsoluteFill>
  );
};

const Words: React.FC<{ text: string; delay: number; step: number; style: React.CSSProperties }> = ({ text, delay, step, style }) => {
  const fr = useCurrentFrame();
  return (
    <div style={{ display: "flex", flexWrap: "wrap", columnGap: "0.28em", ...style }}>
      {text.split(" ").map((w, i) => {
        const sp = spring({ frame: fr - delay - i * step, fps: FPS, config: { damping: 14, stiffness: 140 } });
        return (
          <span key={i} style={{
            display: "inline-block", opacity: sp, filter: `blur(${(1 - sp) * 14}px)`,
            transform: `translateY(${(1 - sp) * 70}px) rotate(${(1 - sp) * 4}deg)`,
          }}>{w}</span>
        );
      })}
    </div>
  );
};

const Feature: React.FC<{ cap: Extract<Cap, { kind: "feature" }> }> = ({ cap }) => {
  const fr = useCurrentFrame();
  const o = out(fr, cap.d, 14);
  const bar = spring({ frame: fr, fps: FPS, config: { damping: 20 } });
  const scrim = interpolate(fr, [0, 12], [0, 1], { extrapolateRight: "clamp" }) * o;
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ opacity: scrim, background: "linear-gradient(90deg, rgba(6,6,14,0.96) 0%, rgba(6,6,14,0.9) 44%, rgba(6,6,14,0) 62%)" }} />
      <AbsoluteFill style={{ justifyContent: "center", paddingLeft: 120, opacity: o, transform: `translateX(${(1 - o) * -60}px)` }}>
        <div style={{ width: 150 * bar, height: 12, borderRadius: 6, background: `linear-gradient(90deg, ${cap.accent}, white)`, marginBottom: 34 }} />
        <Words text={cap.title} delay={3} step={4} style={{
          width: 820, fontSize: 108, lineHeight: 1.02, fontWeight: 900, letterSpacing: -3, color: "white",
          textShadow: `0 0 60px ${cap.accent}88`,
        }} />
        <Words text={cap.text} delay={18} step={2} style={{ width: 760, marginTop: 30, fontSize: 44, fontWeight: 600, color: "rgba(255,255,255,0.82)", lineHeight: 1.25 }} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const Chapter: React.FC<{ cap: Extract<Cap, { kind: "chapter" }> }> = ({ cap }) => {
  const fr = useCurrentFrame();
  const sp = spring({ frame: fr, fps: FPS, config: { damping: 13, stiffness: 160 } });
  const o = out(fr, cap.d, 14);
  const leave = interpolate(fr, [f(cap.d) - 14, f(cap.d)], [1, 1.25], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", background: `rgba(5,5,12,${0.6 * o})` }}>
      <div style={{
        fontSize: 230, fontWeight: 900, letterSpacing: -9, color: "white", opacity: o * sp,
        transform: `scale(${(1.6 - 0.6 * sp) * leave})`, filter: `blur(${(1 - sp) * 20 + (leave - 1) * 40}px)`,
        background: "linear-gradient(100deg, #ffffff 30%, #c4b5fd 60%, #f9a8d4)", WebkitBackgroundClip: "text", color: "transparent",
      }}>{cap.text}</div>
    </AbsoluteFill>
  );
};

const Theme: React.FC<{ cap: Extract<Cap, { kind: "theme" }> }> = ({ cap }) => {
  const fr = useCurrentFrame();
  const flash = interpolate(fr, [0, 10], [0.55, 0], { extrapolateRight: "clamp" });
  const o = out(fr, cap.d, 8);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ background: "white", opacity: flash }} />
      <AbsoluteFill style={{ opacity: o, background: "radial-gradient(ellipse 60% 45% at 18% 100%, rgba(4,4,10,0.85), rgba(4,4,10,0))" }} />
      <AbsoluteFill style={{ justifyContent: "flex-end", paddingLeft: 110, paddingBottom: 90, opacity: o }}>
        <Words text="Theme" delay={0} step={0} style={{ fontSize: 36, fontWeight: 700, color: "rgba(255,255,255,0.75)", letterSpacing: 8, textTransform: "uppercase" }} />
        <Words text={cap.name} delay={2} step={3} style={{
          fontSize: 150, fontWeight: 900, letterSpacing: -5, color: cap.color, lineHeight: 1,
          textShadow: `0 0 50px ${cap.color}aa, 0 10px 40px rgba(0,0,0,0.6)`,
        }} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const Caption: React.FC<{ cap: Cap }> = ({ cap }) =>
  cap.kind === "keys" ? <Keys cap={cap} /> : cap.kind === "feature" ? <Feature cap={cap} />
    : cap.kind === "chapter" ? <Chapter cap={cap} /> : <Theme cap={cap} />;

// ---------------------------------------------------------------- bookends

const Title: React.FC<{ sub: string; size?: number }> = ({ sub, size = 240 }) => {
  const fr = useCurrentFrame();
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      <div style={{ display: "flex" }}>
        {"omacchiato".split("").map((ch, i) => {
          const sp = spring({ frame: fr - i * 3, fps: FPS, config: { damping: 12, stiffness: 150 } });
          return (
            <span key={i} style={{
              display: "inline-block", fontSize: size, fontWeight: 900, letterSpacing: -size * 0.04,
              transform: `translateY(${(1 - sp) * 160}px) rotate(${(1 - sp) * -12}deg)`, opacity: sp,
              background: "linear-gradient(180deg, #ffffff 20%, #d8b4fe 75%, #f472b6)", WebkitBackgroundClip: "text", color: "transparent",
              filter: `drop-shadow(0 20px 60px rgba(168,85,247,0.55))`,
            }}>{ch}</span>
          );
        })}
      </div>
      <Words text={sub} delay={30} step={3} style={{ marginTop: 10, fontSize: 56, fontWeight: 600, color: "rgba(255,255,255,0.85)", justifyContent: "center" }} />
    </AbsoluteFill>
  );
};

const Intro: React.FC = () => {
  const fr = useCurrentFrame();
  const leave = interpolate(fr, [f(INTRO) - 16, f(INTRO)], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.in(Easing.cubic) });
  return (
    <AbsoluteFill style={{ opacity: leave, transform: `scale(${1 + (1 - leave) * 0.6})`, filter: `blur(${(1 - leave) * 16}px)` }}>
      <Title sub="An omarchy-style tiling desktop for macOS" />
    </AbsoluteFill>
  );
};

const Outro: React.FC = () => {
  const fr = useCurrentFrame();
  const pill = spring({ frame: fr - 40, fps: FPS, config: { damping: 15 } });
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ transform: "translateY(-110px)" }}>
        <Title sub="Tiling, themes, and a bar that knows things." size={200} />
      </AbsoluteFill>
      <AbsoluteFill style={{ justifyContent: "flex-end", alignItems: "center", paddingBottom: 170 }}>
        <div style={{
          opacity: pill, transform: `translateY(${(1 - pill) * 50}px) scale(${0.9 + 0.1 * pill})`,
          padding: "26px 54px", borderRadius: 999, background: "rgba(255,255,255,0.1)", border: "1.5px solid rgba(255,255,255,0.25)",
          backdropFilter: "blur(20px)", fontSize: 48, fontWeight: 700, color: "white", letterSpacing: -0.5,
          boxShadow: "0 0 80px rgba(168,85,247,0.45)",
        }}>github.com/wicksipedia/omacchiato</div>
        <div style={{ marginTop: 26, opacity: pill * 0.8, fontSize: 32, fontWeight: 600, color: "white" }}>macOS 26 · Apple Silicon</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- the reel

export const Reel: React.FC = () => (
  <AbsoluteFill style={{ fontFamily: FONT, background: "#07070f" }}>
    <Backdrop />
    <Sequence durationInFrames={f(INTRO)}><Intro /></Sequence>
    {segs.map((seg, i) => (
      <Sequence key={i} from={f(starts[i])} durationInFrames={f(segLen(seg))}>
        <Footage seg={seg} />
        {seg.caps.map((cap, j) => (
          <Sequence key={j} from={f(cap.t)} durationInFrames={f(cap.d)}><Caption cap={cap} /></Sequence>
        ))}
      </Sequence>
    ))}
    <Sequence from={totalFrames - f(OUTRO)}><Outro /></Sequence>
  </AbsoluteFill>
);
