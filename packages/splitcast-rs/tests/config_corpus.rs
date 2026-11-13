use splitcast_rs_core::config::Config;

#[test]
fn frozen_oracle_cases() {
    let cases: serde_json::Value = serde_json::from_str(include_str!("config-corpus.json")).unwrap();
    for case in cases.as_array().unwrap() {
        let input = serde_json::to_vec(&case["input"]).unwrap();
        let expected = case["oracle_accepted"].as_bool().unwrap() && case["reason"].is_null();
        assert_eq!(Config::parse(&input).is_ok(), expected, "{}", case["name"]);
    }
}
