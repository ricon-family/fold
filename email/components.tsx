/** @jsxImportSource emails */

import {
  Bold,
  Card,
  Code,
  Footer,
  Heading,
  HR,
  Item,
  List,
  Paragraph,
  Section as EmailSection,
} from "emails";
import { email } from "emails/src/email";

export function renderReport({
  agent,
  title,
  children,
}: {
  agent: string;
  title: string;
  children: any;
}): string {
  return email({
    body: <>
      <Heading level={1}>{agent} session report</Heading>
      <Paragraph><Bold>{title}</Bold></Paragraph>
      {children}
      <HR />
      <Footer>Generated with fold email components.</Footer>
    </>,
  });
}

export function Section({ title, children }: { title: string; children: any }) {
  return <EmailSection title={title}>{children}</EmailSection>;
}

export function Bullets({ items }: { items: any[] }) {
  return <List>{items.map((item) => <Item>{item}</Item>)}</List>;
}

export function Callout({ title, children }: { title: string; children: any }) {
  return <Card title={title} variant="info">{children}</Card>;
}

export { Code };
