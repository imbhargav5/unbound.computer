import CTA from "./cta";
import FAQ from "./faq";
import { Footer } from "./footer";
import HeroSection from "./hero-section";
import Integration from "./integration";
import LogoCloud from "./logo-cloud";
import Pricing from "./pricing";
import Quotation from "./quotetion";
import Testimonials from "./testimonials";

export async function LandingPage({ locale }: { locale: string }) {
  "use cache";
  return (
    <div>
      <div className="flex flex-col gap-16">
        <HeroSection locale={locale} />
        <LogoCloud />
        <Integration />
        <Quotation />
        <Pricing />
        <Testimonials />
        <FAQ />
        <CTA />
      </div>
      <Footer />
    </div>
  );
}
