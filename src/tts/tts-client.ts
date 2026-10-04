export type TtsClientOptions = {
  baseUrl: string;
  voice: string;
  language: string;
  speed: number;
};

export class TtsClient {
  constructor(private readonly options: TtsClientOptions) {}

  /** Readiness is optional for external URLs, required for automatic local startup. */
  static async checkReadiness(
    baseUrl: string,
    signal: AbortSignal,
  ): Promise<'ready' | 'initializing' | 'unavailable' | 'occupied'> {
    try {
      const response = await fetch(`${baseUrl.replace(/\/$/, '')}/v1/audio/health`, {
        signal: AbortSignal.any([signal, AbortSignal.timeout(1000)]),
        redirect: 'error',
      });
      const body: unknown = await response.json().catch(() => undefined);
      const status = typeof body === 'object' && body !== null && 'status' in body ? body.status : undefined;
      if (response.status === 200 && status === 'ready') return 'ready';
      if (response.status === 503 && status === 'initializing') return 'initializing';
      return 'occupied';
    } catch {
      signal.throwIfAborted();
      return 'unavailable';
    }
  }

  async synthesize(text: string): Promise<Buffer> {
    const form = new FormData();
    form.set('language', this.options.language);
    form.set('text', text);
    form.set('voice', this.options.voice);
    form.set('speed', String(this.options.speed));

    const response = await fetch(`${this.options.baseUrl.replace(/\/$/, '')}/v1/audio/synthesize`, {
      method: 'POST',
      body: form,
    });

    if (!response.ok) {
      const detail = (await response.text()).trim();
      const suffix = detail ? `: ${detail}` : '';
      throw new Error(`TTS request failed with HTTP ${response.status}${suffix}`);
    }

    return Buffer.from(await response.arrayBuffer());
  }
}
