/** @jsxImportSource emails */

import { Bullets, Callout, Code, renderReport, Section } from "../components";

console.log(renderReport({
  agent: "c0da",
  title: "readme API review and action rollout",
  children: <>
    <Section title="Shipped">
      <Bullets items={[
        <>Merged <Code>readme#33</Code> after adversarial API/claim review.</>,
        <>Tagged <Code>readme v0.3.1</Code> for Node 24 action compatibility.</>,
      ]} />
    </Section>

    <Section title="Validation">
      <Bullets items={[
        <>Hosted CI green on readme and emails.</>,
        <>Local suites and README checks passed.</>,
      ]} />
    </Section>

    <Callout title="Next">
      Continue with the next bounded PR review lane.
    </Callout>
  </>,
}));
