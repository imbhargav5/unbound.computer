"use client";
import { Dispatch, SetStateAction, createContext, useState } from "react";
import { useKey } from "rooks";

type SidebarVisibilityContextType = {
  isVisible: boolean;
  toggleVisibility: () => void;
  setVisibility: Dispatch<SetStateAction<boolean>>;
};

export const SidebarVisibilityContext = createContext(
  {} as SidebarVisibilityContextType,
);

export const SidebarVisibilityProvider = ({
  children,
  initialValue = true,
}: {
  children: React.ReactNode;
  initialValue?: boolean;
}) => {
  const [isVisible, setIsVisible] = useState<boolean>(initialValue);

  const toggleVisibility = () => {
    setIsVisible(!isVisible);
  };

  useKey("/", (event) => {
    const isMetaKeyPressed = navigator.userAgent.toLowerCase().includes("mac")
      ? event.metaKey
      : event.ctrlKey;
    if (isMetaKeyPressed) {
      event.preventDefault();
      toggleVisibility();
    }
  });

  return (
    <SidebarVisibilityContext.Provider
      value={{ isVisible, toggleVisibility, setVisibility: setIsVisible }}
    >
      {children}
    </SidebarVisibilityContext.Provider>
  );
};
