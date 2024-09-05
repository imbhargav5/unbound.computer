import { Button } from "@/components/ui/button";
import { CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";
import { acceptTermsOfServiceAction } from "@/data/user/user";
import { useAction } from "next-safe-action/hooks";

type TermsAcceptanceProps = {
  onSuccess: () => void;
};

export function TermsAcceptance({ onSuccess }: TermsAcceptanceProps) {
  const { toast } = useToast();
  const { execute, isPending } = useAction(acceptTermsOfServiceAction, {
    onSuccess: () => {
      toast({ title: "Terms accepted!", description: "Welcome aboard!" });
      onSuccess();
    },
    onError: () => {
      toast({ title: "Failed to accept terms", description: "Please try again.", variant: "destructive" });
    },
  });

  return (
    <>
      <CardHeader className="text-center">
        <CardTitle className="text-3xl font-bold mb-2">🎉 Welcome to <br /> Nextbase Ultimate Demo!</CardTitle>
        <CardDescription className="text-lg">
          We're excited to have you join us. Let's take a moment to ensure we're on the same page.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="bg-primary/10 p-4 rounded-lg">
          <h3 className="text-lg font-semibold mb-2">Why Terms Matter</h3>
          <p className="text-sm text-muted-foreground">
            Our terms of service are designed to create a safe, respectful, and productive environment for all users. They outline our commitments to you and what we expect in return.
          </p>
        </div>
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between bg-secondary/20 rounded-lg p-4 mt-4">
          <div className="flex items-center space-x-3 mb-2 sm:mb-0">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            <div>
              <p className="text-sm font-semibold">Last updated:</p>
              <time dateTime="2024-04-24" className="text-sm text-muted-foreground">
                24th April 2024
              </time>
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <div>
              <p className="text-sm font-semibold">Estimated reading time:</p>
              <p className="text-sm text-muted-foreground">5 minutes</p>
            </div>
          </div>
        </div>
        <blockquote className="border-l-2 pl-6 italic">
          <p className="text-sm text-muted-foreground">
            "By understanding our terms, you're taking an important step in becoming an informed and valued member of our community."
          </p>
        </blockquote>
      </CardContent>
      <CardFooter>
        <Dialog>
          <DialogTrigger asChild>
            <Button className="w-full">View Terms</Button>
          </DialogTrigger>
          <DialogContent className="max-w-3xl">
            <DialogHeader>
              <DialogTitle className="text-2xl font-bold">Terms and Conditions</DialogTitle>
              <DialogDescription>
                Please take a moment to review our terms and conditions. We've made them clear and concise for your convenience.
              </DialogDescription>
            </DialogHeader>
            <div className="max-h-[60vh] overflow-auto p-6 space-y-6 bg-muted rounded-md text-sm">
              <section>
                <h3 className="text-lg font-semibold mb-2">1. Welcome to Our Service</h3>
                <p>We're thrilled to have you on board! Our platform is designed to make your experience seamless and enjoyable. By using our service, you agree to these terms, so let's get acquainted.</p>
              </section>
              <section>
                <h3 className="text-lg font-semibold mb-2">2. Your Account</h3>
                <p>Your account is your gateway to our services. Please keep your login information secure and notify us immediately of any unauthorized use. We take your privacy seriously and have measures in place to protect your data.</p>
              </section>
              <section>
                <h3 className="text-lg font-semibold mb-2">3. Using Our Services</h3>
                <p>We strive to provide top-notch services. In return, we ask that you use them responsibly. This means respecting others' rights, following applicable laws, and not engaging in any harmful activities.</p>
              </section>
              <section>
                <h3 className="text-lg font-semibold mb-2">4. Content and Intellectual Property</h3>
                <p>Your content remains yours, but by uploading it, you grant us a license to use it in connection with our services. We respect intellectual property rights and expect our users to do the same.</p>
              </section>
              <section>
                <h3 className="text-lg font-semibold mb-2">5. Termination</h3>
                <p>We hope you'll stay with us for a long time, but if you need to leave, you can terminate your account at any time. We reserve the right to suspend or terminate accounts that violate our terms.</p>
              </section>
              <section>
                <h3 className="text-lg font-semibold mb-2">6. Changes to Terms</h3>
                <p>As we grow and evolve, our terms may change. We'll notify you of any significant updates. Continuing to use our services after changes means you accept the new terms.</p>
              </section>
              <section>
                <h3 className="text-lg font-semibold mb-2">7. Contact Us</h3>
                <p>We're here to help! If you have any questions about these terms or our services, please don't hesitate to reach out to our support team.</p>
              </section>
            </div>
            <DialogFooter className="mt-4">
              <Button
                onClick={() => execute()}
                disabled={isPending}
                className="w-full sm:w-auto"
              >
                {isPending ? "Accepting..." : "I Accept the Terms"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </CardFooter>
    </>
  );
}
