import { Tab } from "./tab";
import type { TabsNavigationProps } from "./types";

export const TabsNavigation = ({ tabs }: TabsNavigationProps) => (
  <div className="border-b">
    <div className="flex space-x-5">
      {tabs.map((tab) => (
        <Tab key={tab.href} {...tab} />
      ))}
    </div>
  </div>
);
