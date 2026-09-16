export class LlmErrorBodyFormatter {
  public static redactSensitiveText(value: string): string {
    let redacted: string = value;
    redacted = redacted.replace(new RegExp('Bearer\\s+[^\\s,;]+', 'gi'), 'Bearer [REDACTED]');
    redacted = redacted.replace(new RegExp('(api[-_]key|x-api-key|authorization)\\s*[:=]\\s*[^\\s,;]+', 'gi'), '$1=[REDACTED]');
    redacted = redacted.replace(new RegExp('sk-[A-Za-z0-9_-]+', 'g'), 'sk-[REDACTED]');
    return redacted;
  }
}
