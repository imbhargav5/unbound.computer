import CTA from "./cta";
import FAQ from "./faq";
import { Footer } from "./footer";
import HeroSection from "./hero-section";
import Integration from "./integration";
import Pricing from "./pricing";
import Quotation from "./quotetion";

export async function LandingPage() {
  "use cache";
  return (
    <div>
      <div className="flex flex-col gap-16">
        <HeroSection />
        <Integration />
        <Quotation />
        <Pricing />
        <FAQ />
        <CTA />
      </div>
      <Footer />
    </div>
  );
}
