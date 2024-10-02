import { useKey } from 'rooks';

// Remaining arguments of useKey except first two
type UseSafeShortcutOptions = Parameters<typeof useKey>[2];

export function useSafeShortcut(key: string, callback: (e: KeyboardEvent) => void, options?: UseSafeShortcutOptions) {
  useKey(key, (event: KeyboardEvent) => {
    // Ensure the event is not coming from an interactive or editable element
    console.log(event.target);
    if (
      event.target instanceof HTMLElement &&
      (
        event.target.isContentEditable ||
        event.target.tagName === 'INPUT' ||
        event.target.tagName === 'TEXTAREA' ||
        event.target.tagName === 'SELECT' ||
        event.target.tagName === 'BUTTON' ||
        event.target.tagName === 'A' ||
        event.target.closest('form') !== null
      )
    ) {
      return;
    }

    event.preventDefault();
    callback(event);
  }, options);
}
