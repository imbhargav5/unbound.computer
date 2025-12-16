import "./layout.css";

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <div>
      <div className="relative mx-auto space-x-4 md:container sm:space-x-6 sm:px-2 md:px-6 lg:space-x-8 xl:space-x-12">
        <div className="py-8 sm:py-12 lg:py-16 xl:py-20">{children}</div>
      </div>
    </div>
  );
}
