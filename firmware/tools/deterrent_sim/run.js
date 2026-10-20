const fs = require('fs');
WebAssembly.instantiate(fs.readFileSync('deterrent_sim.wasm'), {}).then(({ instance }) => {
  const x = instance.exports;
  const names = ['control', 'vibration_only', 'led_only', 'vibration_led'];
  console.log('deterrent self-test failures:', x.selftest());
  const bootOk = x.boot_buzzer_is_silent_and_never_digitalwritten() === 1;
  console.log('boot: no tone running and the buzzer pin never digitalWritten:', bootOk ? 'YES' : 'NO');
  let bad = bootOk ? 0 : 1;
  console.log('\ncondition        buzzer?  buzzer on (ms)  first..last on   motor on (ms)  buzzer off at end');
  for (let c = 0; c < 4; c++) {
    x.run_condition(c);
    const uses = x.uses_buzzer(c) === 1;
    const total = Number(x.get_buz_total()), first = Number(x.get_buz_first()), last = Number(x.get_buz_last());
    const motor = Number(x.get_motor_total());
    const atEndOn = x.get_buzzer_level_at_end() === 1;
    console.log(`${names[c].padEnd(16)} ${String(uses).padEnd(8)} ${String(total).padStart(13)}   ${String(first).padStart(5)}..${String(last).padEnd(8)}  ${String(motor).padStart(12)}   ${atEndOn ? 'STILL ON' : 'off'}`);
    if (uses && (total < 14990 || total > 15010 || first !== 0)) bad++;      // exactly the 15 s activation window
    if (!uses && total !== 0) bad++;                                         // silent conditions stay silent
    if (atEndOn) bad++;
    if (x.get_buzzer_digitalwrites() !== 0) { bad++; console.log('  !! digitalWrite used on the buzzer pin'); }
    if (x.get_notone_while_silent() !== 0) { bad++; console.log('  !! noTone() called with nothing running'); }
    if (uses && (x.get_tone_calls() !== 1 || x.get_notone_calls() !== 1)) { bad++; console.log('  !! expected exactly one tone() and one noTone()'); }
  }

  // ---- every sensor alone starts a trial immediately (through the real debounce code) ----
  console.log('\nTRIGGER -> TRIAL (sensor goes active at t=0; real 200 ms debounce; outputs per the experiment cycle)');
  console.log('sensor     run  condition        starts  trial started at   motor on   buzzer on   led on');
  const srcNames = ['PIR', 'IR', 'Vibration'];
  const uses = (c) => ({ motor: c === 1 || c === 3, led: c === 2 || c === 3, buzzer: x.uses_buzzer(c) === 1 });
  for (let src = 0; src < 3; src++) {
    for (let run = 0; run < 4; run++) {
      x.run_trigger(src, run === 3 ? 1 : 0);
      const d = Number(x.trig_delay_ms()), m = Number(x.trig_motor_at()), b = Number(x.trig_buzzer_at()), l = Number(x.trig_led_at());
      const cond = x.trig_finished_condition();
      const u = cond >= 0 ? uses(cond) : { motor: false, led: false, buzzer: false };
      const fmt = (v) => (v < 0 ? '-' : v + ' ms');
      console.log(`${srcNames[src].padEnd(10)} ${run + 1}    ${(names[cond] || '?').padEnd(16)} ${x.trig_started() ? 'yes' : 'NO '}     ${String(d).padStart(6)} ms        ${fmt(m).padStart(8)}   ${fmt(b).padStart(9)}   ${fmt(l).padStart(6)}`);
      // started, and exactly after the 200 ms debounce: NO 3 s wait
      if (!x.trig_started() || d < 195 || d > 210) bad++;
      // each output responds in the same tick as the start (+/- the 5 ms tick) when the condition uses it, never otherwise
      if (u.motor !== (m >= 0) || (m >= 0 && m - d > 10)) bad++;
      if (u.buzzer !== (b >= 0) || (b >= 0 && b - d > 10)) bad++;
      if (u.led !== (l >= 0) || (l >= 0 && l - d > 10)) bad++;
      if (!x.trig_second_refused()) { bad++; console.log('  !! a second trigger during a trial was not refused'); }
      if (!x.trig_have_finished()) { bad++; console.log('  !! trial never finished'); }
      if (run === 3) {
        // species attached while the trial runs; wrong id / non-pest refused; after the trial it is too late
        const ok = x.trig_attach_during() === 1 && x.trig_finished_species_is_cockroach() === 1 &&
                   x.trig_attach_wrong_id() === 0 && x.trig_attach_nonpest() === 0 && x.trig_attach_after() === 0;
        console.log(`           late species answer: attached while running=${x.trig_attach_during()}, wrong request id refused=${x.trig_attach_wrong_id() === 0}, non_pest refused=${x.trig_attach_nonpest() === 0}, after the trial refused=${x.trig_attach_after() === 0}, published trial has species=${x.trig_finished_species_is_cockroach() ? 'cockroach' : 'none'}`);
        if (!ok) bad++;
      } else if (!x.trig_finished_species_empty()) { bad++; console.log('  !! species appeared without an answer'); }
    }
  }
  console.log(`tone frequency used: ${x.get_tone_hz_used()} Hz`);
  console.log(bad === 0 ? '\nALL CHECKS PASSED' : `\n${bad} CHECK(S) FAILED`);
  process.exit(bad === 0 ? 0 : 1);
});
