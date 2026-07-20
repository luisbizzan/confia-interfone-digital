export interface Clock {
  now(): Date;
  sleep(ms: number): Promise<void>;
}

export class VirtualClock implements Clock {
  #currentTimeMs: number;

  constructor(initialTime: Date | string | number) {
    const currentTimeMs = new Date(initialTime).getTime();
    if (!Number.isFinite(currentTimeMs)) {
      throw new TypeError("VirtualClock requires a valid initial time");
    }
    this.#currentTimeMs = currentTimeMs;
  }

  now(): Date {
    return new Date(this.#currentTimeMs);
  }

  sleep(ms: number): Promise<void> {
    if (!Number.isFinite(ms) || ms < 0) {
      throw new TypeError(
        "VirtualClock sleep must be a finite non-negative value",
      );
    }
    this.#currentTimeMs += ms;
    return Promise.resolve();
  }
}
