export type BirdsEyeFocusChangeCause = "click" | "keyboard" | "programmatic";

const minimumFocusSoundGapMs = 40;

let lastBirdsEyeFocusSoundAt = 0;
let birdsEyeAudioContextPromise: Promise<AudioContext | null> | null = null;

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
  const audioContext = await getBirdsEyeAudioContext();
  if (!audioContext) {
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

  const startAt = audioContext.currentTime;
  const oscillator = audioContext.createOscillator();
  const filter = audioContext.createBiquadFilter();
  const gain = audioContext.createGain();

  oscillator.type = "square";
  oscillator.frequency.setValueAtTime(1046, startAt);
  oscillator.frequency.exponentialRampToValueAtTime(784, startAt + 0.075);

  filter.type = "lowpass";
  filter.frequency.setValueAtTime(1800, startAt);
  filter.Q.setValueAtTime(0.8, startAt);

  gain.gain.setValueAtTime(0.0001, startAt);
  gain.gain.exponentialRampToValueAtTime(0.035, startAt + 0.006);
  gain.gain.exponentialRampToValueAtTime(0.0001, startAt + 0.085);

  oscillator.connect(filter);
  filter.connect(gain);
  gain.connect(audioContext.destination);

  oscillator.start(startAt);
  oscillator.stop(startAt + 0.09);
  oscillator.onended = () => {
    oscillator.disconnect();
    filter.disconnect();
    gain.disconnect();
  };
}

function getBirdsEyeAudioContext() {
  if (!birdsEyeAudioContextPromise) {
    birdsEyeAudioContextPromise = Promise.resolve(createBirdsEyeAudioContext());
  }

  return birdsEyeAudioContextPromise;
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
