import healthSoundUrl from "../assets/health.wav";

export type BirdsEyeFocusChangeCause = "click" | "keyboard" | "programmatic";

const minimumFocusSoundGapMs = 40;

let lastBirdsEyeFocusSoundAt = 0;
let birdsEyeAudioContextPromise: Promise<AudioContext | null> | null = null;
let birdsEyeFocusBufferPromise: Promise<AudioBuffer | null> | null = null;

export function shouldPlayBirdsEyeFocusSound(
  previousRowId: string | null,
  nextRowId: string | null,
  cause: BirdsEyeFocusChangeCause
) {
  return (
    previousRowId !== nextRowId &&
    nextRowId !== null &&
    (cause === "click" || cause === "keyboard")
  );
}

export function playBirdsEyeFocusSound() {
  const now =
    typeof performance !== "undefined" ? performance.now() : Date.now();
  if (now - lastBirdsEyeFocusSoundAt < minimumFocusSoundGapMs) {
    return;
  }
  lastBirdsEyeFocusSoundAt = now;
  void playBirdsEyeFocusSoundInternal();
}

async function playBirdsEyeFocusSoundInternal() {
  const [audioContext, audioBuffer] = await Promise.all([
    getBirdsEyeAudioContext(),
    getBirdsEyeFocusBuffer(),
  ]);
  if (!(audioContext && audioBuffer)) {
    return;
  }

  if (audioContext.state === "suspended") {
    try {
      await audioContext.resume();
    } catch {
      return;
    }
  }

  if (audioContext.state !== "running") {
    return;
  }

  const source = audioContext.createBufferSource();
  const gain = audioContext.createGain();
  const startAt = audioContext.currentTime;

  source.buffer = audioBuffer;
  gain.gain.setValueAtTime(0.2, startAt);

  source.connect(gain);
  gain.connect(audioContext.destination);

  source.start(startAt);
  source.onended = () => {
    source.disconnect();
    gain.disconnect();
  };
}

function getBirdsEyeAudioContext() {
  if (!birdsEyeAudioContextPromise) {
    birdsEyeAudioContextPromise = Promise.resolve(createBirdsEyeAudioContext());
  }

  return birdsEyeAudioContextPromise;
}

function getBirdsEyeFocusBuffer() {
  if (!birdsEyeFocusBufferPromise) {
    birdsEyeFocusBufferPromise = loadBirdsEyeFocusBuffer();
  }

  return birdsEyeFocusBufferPromise;
}

async function loadBirdsEyeFocusBuffer() {
  const audioContext = await getBirdsEyeAudioContext();
  if (!audioContext || typeof fetch !== "function") {
    return null;
  }

  try {
    const response = await fetch(healthSoundUrl);
    if (!response.ok) {
      return null;
    }
    const arrayBuffer = await response.arrayBuffer();
    return await audioContext.decodeAudioData(arrayBuffer);
  } catch {
    return null;
  }
}

function createBirdsEyeAudioContext() {
  if (typeof window === "undefined") {
    return null;
  }

  const AudioContextConstructor =
    window.AudioContext ??
    (window as Window & { webkitAudioContext?: typeof AudioContext })
      .webkitAudioContext;

  if (!AudioContextConstructor) {
    return null;
  }

  try {
    return new AudioContextConstructor();
  } catch {
    return null;
  }
}
