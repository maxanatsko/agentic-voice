export type TtsClientOptions = {
  baseUrl: string;
  voice: string;
  language: string;
  speed: number;
};

export class TtsClient {
  constructor(private readonly options: TtsClientOptions) {}

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
