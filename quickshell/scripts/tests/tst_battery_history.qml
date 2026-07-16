import QtQuick
import QtTest
import "../../desktop/nc/battery-history.js" as BatteryHistory

TestCase {
    name: "BatteryHistory"

    readonly property double now: new Date(2026, 6, 15, 17, 30, 0, 0).getTime()

    function payload(rows) {
        return JSON.stringify({ type: "a(udu)", data: [rows] })
    }

    function test_parses_filters_and_sorts_upower_rows() {
        let rows = BatteryHistory.parseBusctl(payload([
            [200, 80, 2],
            [150, 0, 0],
            [100, 90, 1]
        ]))
        compare(rows.length, 2)
        compare(rows[0].timestamp, 100000)
        compare(rows[0].level, 90)
        compare(rows[0].state, 1)
        compare(rows[1].timestamp, 200000)
    }

    function test_builds_96_slots_and_marks_charge_states() {
        let start = new Date(2026, 6, 14, 18, 0, 0, 0).getTime()
        let result = BatteryHistory.buildBuckets(payload([
            [Math.floor((start + 30 * 60 * 1000) / 1000), 82, 1],
            [Math.floor((start + 60 * 60 * 1000) / 1000), 81, 2]
        ]), now)

        compare(result.samples.length, 96)
        verify(result.samples[2].has)
        verify(result.samples[2].charging)
        verify(result.samples[4].has)
        verify(!result.samples[4].charging)
        compare(result.samples[4].level, 81)
    }

    function test_invalid_json_yields_empty_history() {
        compare(BatteryHistory.parseBusctl("not json").length, 0)
        let result = BatteryHistory.buildBuckets("not json", now)
        compare(result.samples.length, 96)
        verify(!result.samples[0].has)
    }
}
