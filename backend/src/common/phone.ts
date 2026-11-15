export function normalizeKenyanPhone(value: string): string {
  const compact = value.trim().replace(/[\s()-]/g, "");
  if (compact.startsWith("+254")) return `0${compact.slice(4)}`;
  if (compact.startsWith("254")) return `0${compact.slice(3)}`;
  return compact;
}

export const KENYAN_MOBILE_PATTERN = /^(?:\+?254[\s()-]?|0)[17](?:[\s()-]?\d){8}$/;
