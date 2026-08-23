import assert from 'node:assert/strict';
import test from 'node:test';
import { prepareSpeechText } from '../src/voice/voice-service.js';

test('normalizes whitespace before speaking', () => {
  assert.equal(prepareSpeechText('  Review\ncomplete.   Two issues.  ', 100), 'Review complete. Two issues.');
});

test('rejects empty speech', () => {
  assert.throws(() => prepareSpeechText('   ', 100), /cannot be empty/i);
});

test('rejects text above the configured limit', () => {
  assert.throws(() => prepareSpeechText('123456', 5), /Summarize before speaking/);
});
