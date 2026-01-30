import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { faq } from "@/data/anon/faq";

export default function FAQ() {
  return (
    <section
      className="mx-auto flex max-w-3xl flex-col items-center justify-center space-y-8 px-6 py-20"
      id="faq"
    >
      <div className="text-center">
        <p className="mb-4 font-medium text-sm text-white/40 uppercase tracking-widest">
          FAQ
        </p>
        <h2 className="font-light text-3xl text-white lg:text-4xl">
          Frequently Asked Questions
        </h2>
      </div>

      <Accordion className="w-full" collapsible type="single">
        {faq.map((item, i) => (
          <AccordionItem
            className="border-white/10"
            key={i}
            value={`item-${i + 1}`}
          >
            <AccordionTrigger className="text-left text-white hover:text-white/80 hover:no-underline">
              {item.question}
            </AccordionTrigger>
            <AccordionContent className="text-white/50">
              {item.answer}
            </AccordionContent>
          </AccordionItem>
        ))}
      </Accordion>
    </section>
  );
}
