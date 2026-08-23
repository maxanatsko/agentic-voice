export type NvidiaTtsOptions = {
  baseUrl: string;
  voice: string;
  language: string;
};

export class NvidiaTtsClient {
  constructor(private readonly options: NvidiaTtsOptions) {}

  async synthesize(text: string): Promise<Buffer> {
    const form = new FormData();
    form.set('language', this.options.language);
    form.set('text', text);
    form.set('voice', this.options.voice);

    const response = await fetch(`${this.options.baseUrl.replace(/\/$/, '')}/v1/audio/synthesize`, {
      method: 'POST',
      body: form,
    });

    if (!response.ok) {
      const detail = (await response.text()).trim();
      const suffix = detail ? `: ${detail}` : '';
      throw new Error(`NVIDIA TTS request failed with HTTP ${response.status}${suffix}`);
    }

    return Buffer.from(await response.arrayBuffer());
  }
}
