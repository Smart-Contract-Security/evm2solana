// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PhaseScheduleLib
 * @notice Pure state-management library for 4 time phases.
 *
 * Phase design:
 * - There is one start time and three closing timepoints.
 * - These timepoints create four business phases:
 *
 *   NOT_STARTED: timestamp < startAt
 *   PHASE_1:     [startAt, phase1End)
 *   PHASE_2:     [phase1End, phase2End)
 *   PHASE_3:     [phase2End, phase3End)
 *   PHASE_4:     [phase3End, infinity)
 *
 * Default duration relationship:
 * - PHASE_1: 24 hours
 * - PHASE_2: user-defined duration x
 * - PHASE_3: 14 days
 * - PHASE_4: open-ended / no deadline
 *
 * Extension rules:
 * - PHASE_1 can be extended, never shortened.
 * - PHASE_2 can be extended, never shortened.
 * - If PHASE_1 is extended, phase1End / phase2End / phase3End all shift forward.
 * - If PHASE_2 is extended, phase2End / phase3End shift forward.
 * - PHASE_3 defaults to 14 days and can also be extended, never shortened.
 * - If PHASE_3 is extended, only phase3End shifts forward.
 * - PHASE_4 is always open-ended.
 *
 * Failure rule:
 * - If PHASE_1 fails, phase1End = phase2End = phase3End = failureEffectiveAt.
 * - This collapses PHASE_2 and PHASE_3, and the schedule immediately enters PHASE_4.
 * - After PHASE_1 failure, extending PHASE_2 or PHASE_3 is forbidden.
 * - In practice, all phase extension functions are frozen after PHASE_1 failure.
 *
 * Important:
 * - This library only manages time state.
 * - It does not handle permissions, business settlement, token transfer, pause logic, or events.
 * - The outer contract should enforce access control and emit events.
 */
library PhaseScheduleLib {
    uint64 internal constant DEFAULT_PHASE1_DURATION = 24 hours;
    uint64 internal constant DEFAULT_PHASE3_DURATION = 14 days;

    enum Stage {
        NOT_STARTED,
        PHASE_1,
        PHASE_2,
        PHASE_3,
        PHASE_4
    }

    struct Schedule {
        uint64 startAt;
        uint64 phase1End;
        uint64 phase2End;
        uint64 phase3End;
        bool initialized;
        bool phase1Failed;
    }

    error AlreadyInitialized();
    error NotInitialized();
    error InvalidStartTime();
    error InvalidDuration();
    error InvalidTimepoint();
    error ZeroExtension();
    error CannotShorten();
    error ScheduleCollapsed();
    error Phase1AlreadyEnded();
    error TimestampOverflow();

    // -------------------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------------------

    /**
     * @notice Initialize with default phase1 = 24h and phase3 = 14 days.
     * @param self Schedule storage pointer.
     * @param startAt Start timestamp.
     * @param phase2Duration_ User-defined phase2 duration in seconds.
     */
    function initialize(Schedule storage self, uint64 startAt, uint64 phase2Duration_) internal {
        initializeCustom(self, startAt, DEFAULT_PHASE1_DURATION, phase2Duration_, DEFAULT_PHASE3_DURATION);
    }

    /**
     * @notice Initialize with custom durations. Mainly useful for testing or special deployments.
     * @dev Production contracts should usually use `initialize`.
     */
    function initializeCustom(
        Schedule storage self,
        uint64 startAt,
        uint64 phase1Duration_,
        uint64 phase2Duration_,
        uint64 phase3Duration_
    ) internal {
        if (self.initialized) revert AlreadyInitialized();
        if (startAt == 0) revert InvalidStartTime();
        if (phase1Duration_ == 0 || phase2Duration_ == 0 || phase3Duration_ == 0) {
            revert InvalidDuration();
        }

        uint64 p1 = _add64(startAt, phase1Duration_);
        uint64 p2 = _add64(p1, phase2Duration_);
        uint64 p3 = _add64(p2, phase3Duration_);

        self.startAt = startAt;
        self.phase1End = p1;
        self.phase2End = p2;
        self.phase3End = p3;
        self.initialized = true;
        self.phase1Failed = false;
    }

    // -------------------------------------------------------------------------
    // Stage reading
    // -------------------------------------------------------------------------

    function stageNow(Schedule storage self) internal view returns (Stage) {
        return stageAt(self, uint64(block.timestamp));
    }

    function stageAt(Schedule storage self, uint64 timestamp) internal view returns (Stage) {
        _requireInitialized(self);

        if (timestamp < self.startAt) return Stage.NOT_STARTED;
        if (timestamp < self.phase1End) return Stage.PHASE_1;
        if (timestamp < self.phase2End) return Stage.PHASE_2;
        if (timestamp < self.phase3End) return Stage.PHASE_3;
        return Stage.PHASE_4;
    }

    function isNotStarted(Schedule storage self, uint64 timestamp) internal view returns (bool) {
        return stageAt(self, timestamp) == Stage.NOT_STARTED;
    }

    function isPhase1(Schedule storage self, uint64 timestamp) internal view returns (bool) {
        return stageAt(self, timestamp) == Stage.PHASE_1;
    }

    function isPhase2(Schedule storage self, uint64 timestamp) internal view returns (bool) {
        return stageAt(self, timestamp) == Stage.PHASE_2;
    }

    function isPhase3(Schedule storage self, uint64 timestamp) internal view returns (bool) {
        return stageAt(self, timestamp) == Stage.PHASE_3;
    }

    function isPhase4(Schedule storage self, uint64 timestamp) internal view returns (bool) {
        return stageAt(self, timestamp) == Stage.PHASE_4;
    }

    function hasStarted(Schedule storage self, uint64 timestamp) internal view returns (bool) {
        _requireInitialized(self);
        return timestamp >= self.startAt;
    }

    function isOpenEndedPhase(Schedule storage self, uint64 timestamp) internal view returns (bool) {
        return stageAt(self, timestamp) == Stage.PHASE_4;
    }

    function isCollapsedByPhase1Failure(Schedule storage self) internal view returns (bool) {
        _requireInitialized(self);
        return self.phase1Failed;
    }

    // -------------------------------------------------------------------------
    // Timepoint reading
    // -------------------------------------------------------------------------

    function bounds(Schedule storage self)
        internal
        view
        returns (uint64 startAt, uint64 phase1End, uint64 phase2End, uint64 phase3End)
    {
        _requireInitialized(self);
        return (self.startAt, self.phase1End, self.phase2End, self.phase3End);
    }

    function phase1Duration(Schedule storage self) internal view returns (uint64) {
        _requireInitialized(self);
        if (self.phase1End <= self.startAt) return 0;
        return self.phase1End - self.startAt;
    }

    function phase2Duration(Schedule storage self) internal view returns (uint64) {
        _requireInitialized(self);
        if (self.phase2End <= self.phase1End) return 0;
        return self.phase2End - self.phase1End;
    }

    function phase3Duration(Schedule storage self) internal view returns (uint64) {
        _requireInitialized(self);
        if (self.phase3End <= self.phase2End) return 0;
        return self.phase3End - self.phase2End;
    }

    function secondsUntilNextBoundary(Schedule storage self, uint64 timestamp)
        internal
        view
        returns (uint64 secondsLeft)
    {
        Stage s = stageAt(self, timestamp);

        if (s == Stage.NOT_STARTED) return self.startAt - timestamp;
        if (s == Stage.PHASE_1) return self.phase1End - timestamp;
        if (s == Stage.PHASE_2) return self.phase2End - timestamp;
        if (s == Stage.PHASE_3) return self.phase3End - timestamp;
        return type(uint64).max; // PHASE_4 is open-ended.
    }

    // -------------------------------------------------------------------------
    // Extension functions
    // -------------------------------------------------------------------------

    /**
     * @notice Extend phase1 by extra seconds.
     * @dev phase1End, phase2End and phase3End all shift forward by the same amount.
     */
    function extendPhase1(Schedule storage self, uint64 extraSeconds) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);
        if (extraSeconds == 0) revert ZeroExtension();

        self.phase1End = _add64(self.phase1End, extraSeconds);
        self.phase2End = _add64(self.phase2End, extraSeconds);
        self.phase3End = _add64(self.phase3End, extraSeconds);
    }

    /**
     * @notice Extend phase2 by extra seconds.
     * @dev phase2End and phase3End shift forward by the same amount.
     */
    function extendPhase2(Schedule storage self, uint64 extraSeconds) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);
        if (extraSeconds == 0) revert ZeroExtension();

        self.phase2End = _add64(self.phase2End, extraSeconds);
        self.phase3End = _add64(self.phase3End, extraSeconds);
    }

    /**
     * @notice Set a later phase1 end time. Cannot shorten.
     * @dev If phase1End is moved forward by delta, all later closing timepoints shift by delta.
     */
    function setPhase1End(Schedule storage self, uint64 newPhase1End) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);
        if (newPhase1End <= self.phase1End) revert CannotShorten();

        uint64 delta = newPhase1End - self.phase1End;
        self.phase1End = newPhase1End;
        self.phase2End = _add64(self.phase2End, delta);
        self.phase3End = _add64(self.phase3End, delta);
    }

    /**
     * @notice Set a later phase2 end time. Cannot shorten.
     * @dev If phase2End is moved forward by delta, phase3End shifts by delta.
     */
    function setPhase2End(Schedule storage self, uint64 newPhase2End) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);
        if (newPhase2End <= self.phase2End) revert CannotShorten();

        uint64 delta = newPhase2End - self.phase2End;
        self.phase2End = newPhase2End;
        self.phase3End = _add64(self.phase3End, delta);
    }

    /**
     * @notice Set phase1 duration from startAt. Cannot shorten existing phase1 duration.
     */
    function setPhase1Duration(Schedule storage self, uint64 newPhase1Duration) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);
        if (newPhase1Duration == 0) revert InvalidDuration();

        uint64 newPhase1End = _add64(self.startAt, newPhase1Duration);
        if (newPhase1End <= self.phase1End) revert CannotShorten();

        setPhase1End(self, newPhase1End);
    }

    /**
     * @notice Set phase2 duration from phase1End. Cannot shorten existing phase2 duration.
     */
    function setPhase2Duration(Schedule storage self, uint64 newPhase2Duration) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);
        if (newPhase2Duration == 0) revert InvalidDuration();

        uint64 oldDuration = self.phase2End - self.phase1End;
        if (newPhase2Duration <= oldDuration) revert CannotShorten();

        uint64 delta = newPhase2Duration - oldDuration;
        self.phase2End = _add64(self.phase2End, delta);
        self.phase3End = _add64(self.phase3End, delta);
    }

    /**
     * @notice Extend phase3 by extra seconds.
     * @dev Only phase3End shifts forward. PHASE_4 starts later.
     */
    function extendPhase3(Schedule storage self, uint64 extraSeconds) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);
        if (extraSeconds == 0) revert ZeroExtension();

        self.phase3End = _add64(self.phase3End, extraSeconds);
    }

    /**
     * @notice Set a later phase3 end time. Cannot shorten.
     * @dev Only phase3End shifts forward. PHASE_4 starts later.
     */
    function setPhase3End(Schedule storage self, uint64 newPhase3End) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);
        if (newPhase3End <= self.phase3End) revert CannotShorten();

        self.phase3End = newPhase3End;
    }

    /**
     * @notice Set phase3 duration from phase2End. Cannot shorten existing phase3 duration.
     */
    function setPhase3Duration(Schedule storage self, uint64 newPhase3Duration) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);
        if (newPhase3Duration == 0) revert InvalidDuration();

        uint64 oldDuration = self.phase3End - self.phase2End;
        if (newPhase3Duration <= oldDuration) revert CannotShorten();

        self.phase3End = _add64(self.phase2End, newPhase3Duration);
    }

    // -------------------------------------------------------------------------
    // Phase1 failure collapse
    // -------------------------------------------------------------------------

    /**
     * @notice Collapse the schedule into phase4 because phase1 failed.
     * @param failureEffectiveAt The effective timestamp of failure.
     *
     * Requirement:
     * - failureEffectiveAt must be within the original/current PHASE_1 range:
     *   startAt <= failureEffectiveAt <= phase1End.
     *
     * Effect:
     * - phase1End = phase2End = phase3End = failureEffectiveAt.
     * - For timestamp >= failureEffectiveAt, stageAt(...) returns PHASE_4.
     * - PHASE_2 and PHASE_3 become zero-length and are skipped.
     * - phase1Failed is set to true.
     * - After this, extendPhase2 / setPhase2End / setPhase2Duration are rejected.
     * - After this, extendPhase3 / setPhase3End / setPhase3Duration are rejected.
     */
    function markPhase1Failed(Schedule storage self, uint64 failureEffectiveAt) internal {
        _requireInitialized(self);
        _requireNotCollapsed(self);

        if (failureEffectiveAt < self.startAt) revert InvalidTimepoint();
        if (failureEffectiveAt > self.phase1End) revert Phase1AlreadyEnded();

        self.phase1End = failureEffectiveAt;
        self.phase2End = failureEffectiveAt;
        self.phase3End = failureEffectiveAt;
        self.phase1Failed = true;
    }

    /**
     * @notice Collapse phase1 failure using current block timestamp.
     * @dev If the caller may execute after phase1 end, use `markPhase1Failed(self, self.phase1End)` instead.
     */
    function markPhase1FailedNow(Schedule storage self) internal {
        markPhase1Failed(self, uint64(block.timestamp));
    }

    // -------------------------------------------------------------------------
    // Require helpers for outer business contracts
    // -------------------------------------------------------------------------

    function requireStage(Schedule storage self, Stage expectedStage, uint64 timestamp) internal view {
        if (stageAt(self, timestamp) != expectedStage) revert InvalidTimepoint();
    }

    function requireStageNow(Schedule storage self, Stage expectedStage) internal view {
        requireStage(self, expectedStage, uint64(block.timestamp));
    }

    function requireBeforePhase4(Schedule storage self, uint64 timestamp) internal view {
        if (stageAt(self, timestamp) == Stage.PHASE_4) revert InvalidTimepoint();
    }

    function requirePhase4(Schedule storage self, uint64 timestamp) internal view {
        if (stageAt(self, timestamp) != Stage.PHASE_4) revert InvalidTimepoint();
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _requireInitialized(Schedule storage self) private view {
        if (!self.initialized) revert NotInitialized();
    }

    function _requireNotCollapsed(Schedule storage self) private view {
        if (self.phase1Failed) revert ScheduleCollapsed();
    }

    function _add64(uint64 a, uint64 b) private pure returns (uint64) {
        unchecked {
            uint64 c = a + b;
            if (c < a) revert TimestampOverflow();
            return c;
        }
    }
}
