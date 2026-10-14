import * as store from "./store.ts";

export const SEATS_PER_EVENT = 10;

const seatKey = (eventId: string) => `event:${eventId}:seats_taken`;

/**
 * Try to reserve one seat at an event for a customer.
 *
 * Uses a single atomic INCR rather than read-then-write: a get/check/set
 * sequence spans multiple round trips, so concurrent requests could all read
 * the same count and oversell the event. INCR hands every caller a unique
 * ticket number, and only tickets 1..SEATS_PER_EVENT win a seat. Once the
 * event is sold out, the counter keeps climbing past the limit, which is
 * harmless: every later caller sees a number > SEATS_PER_EVENT and is refused.
 */
export async function reserveSeat(eventId: string, customerId: string): Promise<boolean> {
  void customerId; // not needed to allocate a seat; see report on dedupe
  const ticket = await store.incr(seatKey(eventId));
  return ticket <= SEATS_PER_EVENT;
}
