R = require 'ramda'
{Some, None} = require 'fantasy-options'
policy = require '../src/index'

# :: [e] -> RetryPolicy e -> [Number]
logPolicy = R.curry((es, p) ->
  step = (s, e) ->
    [pol, ns] = s
    pol.chain((f) -> f(e))
      .fold(
        ((t) -> [Some(t._2), R.append(t._1, ns)]),
             -> [None, ns])

  R.reduce(step, [Some(p), []], es)[1])

describe "policy", ->
  describe "both", ->
    it "should use the max duration of both policies", ->
      p1 = policy.orElse(
        policy.both(policy.constant(7), policy.limit(2)),
        policy.constant(3))
      p2 = policy.constant(5)

      expect(logPolicy(['e', 'e', 'e', 'e'], policy.both(p1, p2)))
        .to.eql([7, 7, 5, 5])

    it "should halt when first policy halts", ->
      expect(policy.both(policy.halt, policy.constant(10))).to.beEmpty

    it "should halt when second policy halts", ->
      expect(policy.both(policy.constant(10), policy.halt)).to.beEmpty

    it "should be associative", ->
      p1 = policy.constant(5)
      p2 = policy.exponentialBackoff(1)
      p3 = policy.limit(4)
      es = ['e', 'e', 'e', 'e', 'e', 'e']

      expect(logPolicy(es, policy.both(p1, policy.both(p2, p3))))
        .to.eql(logPolicy(es, policy.both(policy.both(p1, p2), p3)))

  describe "orElse", ->
    p1 = policy.both(policy.constant(10), policy.retryWhen(R.eq('e1')))
    p2 = policy.constant(20)
    es = ['e', 'e1', 'e3', 'e1', 'e']

    it "should use the first until it halts, then the second", ->
      expect(logPolicy(es, policy.orElse(p1, p2)))
        .to.eql([20, 10, 20, 10, 20])

    it "should be associative", ->
      p0 = policy.both(policy.constant(2), policy.limit(2))
      expect(logPolicy(es, policy.orElse(p0, policy.orElse(p1, p2))))
        .to.eql(logPolicy(es, policy.orElse(policy.orElse(p0, p1), p2)))

  describe "immediately", ->
    es = ['e', 'e']

    it "should be the left identity for `both`", ->
      expect(logPolicy(es, policy.both(policy.immediately, policy.constant(1))))
        .to.eql([1, 1])

    it "should be the right identity for `both`", ->
      expect(logPolicy(es, policy.both(policy.constant(1), policy.immediately)))
        .to.eql([1, 1])

  describe "halt", ->
    it "should be the left identity for `orElse`", ->
      expect(logPolicy(['e', 'e'], policy.orElse(policy.halt, policy.constant(2))))
        .to.eql([2, 2])

    it "should be the right identity for `orElse`", ->
      expect(logPolicy(['e', 'e'], policy.orElse(policy.constant(2), policy.halt)))
        .to.eql([2, 2])

  describe "exponentialBackoff", ->
    it "should retry every (2^n) * K milliseconds", ->
      expect(logPolicy(['a', 'a', 'a'], policy.exponentialBackoff(3)))
        .to.eql([3, 6, 12])

  describe "limit", ->
    it "should halt after N attempts", ->
      expect(logPolicy(['a', 'a', 'a', 'a'], policy.limit(2)))
        .to.eql([0, 0])

    it "should halt immediately when n === 0", ->
      expect(logPolicy(['a', 'a'], policy.limit(0))).to.beEmpty

    it "shoud halt immediately when n < 0", ->
      expect(logPolicy(['a', 'a'], policy.limit(-1))).to.beEmpty

  describe "retryWhen", ->
    it "should halt when the predicate returns false", ->
      p = policy.retryWhen(R.eq('e'))
      expect(logPolicy(['e', 'e', 'a', 'e', 'e'], p))
        .to.eql([0, 0])

  describe "capDelay", ->
    it "should limit the delay of the policy to `n`", ->
      p = policy.capDelay(30, policy.exponentialBackoff(5))
      expect(logPolicy(['a', 'a', 'a', 'a', 'a'], p))
        .to.eql([5, 10, 20, 30, 30])

  describe "repeat", ->
    it "should repeat the given policy forever", ->
      p = policy.both(policy.exponentialBackoff(2), policy.limit(2))
      expect(logPolicy(['a', 'a', 'a', 'a', 'a', 'a'], policy.repeat(p)))
        .to.eql([2, 4, 2, 4, 2, 4])

