R = require 'ramda'
{Some, None} = require 'fantasy-options'
{Tuple2} = require 'fantasy-tuples'
{lift2} = require 'fantasy-sorcery'

# type RetryPolicy e = e -> Option (Number, RetryPolicy e)
#
# A RetryPolicy is a function of an error type, e, which returns a Tuple2 of a
# millisecond delay and the policy to use to handle the next error, or None.
#
# Delays should be natural numbers, though there is nothing enforcing this.
# Behavior when a RetryPolicy results in a negative delay is undefined.
#
# RetryPolicy e forms a Monoid (mappend, mzero) with (both, immediately) as
# well as with (orElse, halt)
#

# :: RetryPolicy e -> RetryPolicy e -> RetryPolicy e
#
# Combine two RetryPolicies by running them both and retrying after the maximum
# of both delays, halting when either halts.
#
both = R.curry((p1, p2) ->
  both0 = (t1, t2) -> Tuple2(Math.max(t1._1, t2._1), both(t1._2, t2._2))
  (e) -> lift2(both0, p1(e), p2(e)))

# :: RetryPolicy e -> RetryPolicy e -> RetryPolicy e
#
# Try the first policy, if it halts, try the second.
#
orElse = R.curry((p1, p2) -> (e) ->
  p1(e).fold(
    ((t) -> Some(Tuple2(t._1, orElse(t._2, p2)))),
         -> p2(e).map((t) -> Tuple2(t._1, orElse(p1, t._2)))))

# :: RetryPolicy e -> RetryPolicy e
#
# Given an inital policy, P, use it until it halts, then start over with the
# original.
#
repeat = (p) -> orElse(p, p)

# :: Number -> RetryPolicy e -> RetryPolicy e
#
# Limit the delay of given retry policy to at most n.
#
capDelay = R.curry((maxDelay, p) -> (e) ->
  p(e).map((t) -> Tuple2(Math.min(maxDelay, t._1), capDelay(maxDelay, t._2))))

# :: (e -> Option[Number]) -> RetryPolicy e
#
# Construct a RetryPolicy from a function that returns an optional delay for
# an error, using the function for every attempt.
#
simple = (f) -> (e) ->
  f(e).map((n) -> Tuple2(n, simple(f)))

# :: forall e. Number -> RetryPolicy e
#
# Retry every n milliseconds forever.
#
constant = (n) ->
  simple(R.always(Some(n)))

# :: forall e. RetryPolicy e
#
# Retry immediately (i.e. with zero delay) forever.
#
immediately = constant(0)

# :: forall e. RetryPolicy e
#
# A RetryPolicy that never retries.
#
halt = R.always(None)

# :: forall e. Number -> RetryPolicy e
#
# Retry forever, starting with a delay of n and increasing by a factor of 2
# on each attempt.
#
exponentialBackoff = (n) -> (_) ->
  Some(Tuple2(n, exponentialBackoff(n * 2)))

# :: forall e. Number -> RetryPolicy e
#
# Retry at most n times.
#
limit = (n) -> (_) ->
  if n < 1
    None
  else
    Some(Tuple2(0, limit(n - 1)))

# :: (e -> Boolean) -> RetryPolicy e
#
# Retry when the predicate returns true.
#
retryWhen = (f) -> (e) ->
  if f(e)
    Some(Tuple2(0, retryWhen(f)))
  else
    None

module.exports = {
  both,
  orElse,
  repeat,
  capDelay,
  simple,
  constant,
  immediately,
  halt,
  exponentialBackoff,
  limit,
  retryWhen
}

