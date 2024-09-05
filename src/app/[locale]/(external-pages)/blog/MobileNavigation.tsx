'use client';
import { Dialog } from '@headlessui/react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { ComponentProps, useState } from 'react';

function MenuIcon(props: ComponentProps<'svg'>) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      strokeWidth="2"
      strokeLinecap="round"
      {...props}
    >
      <path d="M4 7h16M4 12h16M4 17h16" />
    </svg>
  );
}

function CloseIcon(props: ComponentProps<'svg'>) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      strokeWidth="2"
      strokeLinecap="round"
      {...props}
    >
      <path d="M5 5l14 14M19 5l-14 14" />
    </svg>
  );
}

export function MobileNavigation() {
  const router = useRouter();
  const [isOpen, setIsOpen] = useState(false);

  // useEffect(() => {
  //   if (!isOpen) return

  //   function onRouteChange() {
  //     setIsOpen(false)
  //   }

  //   router.events.on('routeChangeComplete', onRouteChange)
  //   router.events.on('routeChangeError', onRouteChange)

  //   return () => {
  //     router.events.off('routeChangeComplete', onRouteChange)
  //     router.events.off('routeChangeError', onRouteChange)
  //   }
  // }, [router, isOpen])

  return (
    <>
      <button
        type="button"
        onClick={() => setIsOpen(true)}
        className="relative"
        aria-label="Open navigation"
      >
        <MenuIcon className="h-6 w-6 stroke-current" />
      </button>
      <Dialog
        open={isOpen}
        onClose={setIsOpen}
        className="fixed inset-0 z-50 flex items-start overflow-y-auto bg-neutral-900 pr-10 backdrop-blur lg:hidden"
        aria-label="Navigation"
      >
        <Dialog.Panel className="min-h-full w-full max-w-xs bg-neutral-100 px-4 pb-12 pt-5 sm:px-6">
          <div className="flex items-center">
            <button
              type="button"
              onClick={() => setIsOpen(false)}
              aria-label="Close navigation"
            >
              <CloseIcon className="h-6 w-6 stroke-current" />
            </button>
            <Link href="/" className="block" aria-label="Home page">
              <img
                src="https://usenextbase.com/logos/nextbase/Logo%2006.png"
                className="h-9 block sm:h-9"
                alt="Nextbase Logo"
              />
            </Link>
          </div>
        </Dialog.Panel>
      </Dialog>
    </>
  );
}
