import { incr } from "./store.ts";

export const SEATS_PER_EVENT = 10;

/**
 * Try to reserve one seat for an event.
 *
 * The store only offers an atomic INCR, so we claim a seat by incrementing a
 * per-event counter and looking at the value we got back. Each caller gets a
 * unique number: 1..10 win a seat, anything higher is sold out. There is no
 * read-then-write step, so concurrent callers cannot oversell.
 *
 * The counter keeps climbing on rejected attempts; it records attempts, not
 * seats, and only the first SEATS_PER_EVENT values ever count.
 *
 * Note: customerId is not used to deduplicate; the same customer calling twice
 * takes two seats. Per-customer limits would need an atomic set-if-absent,
 * which the store client does not expose.
 */
export async function reserveSeat(eventId: string, customerId: string): Promise<boolean> {
  void customerId;
  const claimed = await incr(`event:${eventId}:seats-claimed`);
  return claimed <= SEATS_PER_EVENT;
}
