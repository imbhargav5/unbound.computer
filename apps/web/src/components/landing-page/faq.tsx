import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { faq } from "@/data/anon/faq";
import Icons from "../icons";
import TitleBlock from "../title-block";

export default function FAQ() {
  return (
    <section className="mx-auto flex max-w-6xl flex-col items-center justify-center space-y-6 px-6 py-16">
      <TitleBlock
        icon={<Icons.questionMark />}
        section="FAQ"
        subtitle="Get detailed answers to common inquiries. Enhance your understanding of our offerings and policies."
        title="Frequently Asked Questions"
      />
      {faq.map((item, i) => (
        <Accordion
          className="w-full max-w-3xl"
          collapsible
          key={i}
          type="single"
        >
          <AccordionItem value={`item-${i + 1}`}>
            <AccordionTrigger>{item.question}</AccordionTrigger>
            <AccordionContent>{item.answer}</AccordionContent>
          </AccordionItem>
        </Accordion>
      ))}
    </section>
  );
}
