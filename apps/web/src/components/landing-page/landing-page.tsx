import CTA from "./cta";
import FAQ from "./faq";
import { Footer } from "./footer";
import HeroSection from "./hero-section";
import HowItWorks from "./how-it-works";
import Integration from "./integration";
import Quotation from "./quotetion";

export async function LandingPage() {
  "use cache";
  return (
    <div>
      <HeroSection />
      <HowItWorks />
      <Integration />
      <Quotation />
      <FAQ />
      <CTA />
      <Footer />
    </div>
  );
}
