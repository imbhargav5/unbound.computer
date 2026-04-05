import type { FormEvent, ReactNode } from "react";
import {
  ArrowLeftIcon,
  BellIcon,
  CopyIcon,
  CheckIcon,
  HomeIcon,
  LaptopIcon,
  PaletteIcon,
  PlusIcon,
  ShieldIcon,
  Trash2Icon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
} from "@/components/ui/sidebar";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";
import type {
  DesktopSettings,
  RuntimeCapabilities,
  TerminalPresetRecord,
} from "@/lib/types";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type SettingsSection = "appearance" | "notifications" | "privacy" | "about";
type ThemeMode = "system" | "light" | "dark";
type FontSizePreset = "small" | "medium" | "large";

interface SelectOption<T extends string> {
  label: string;
  value: T;
}

interface BootstrapInfo {
  expected_app_version: string;
  daemon_info?: { daemon_version: string } | null;
  socket_path: string;
  base_dir: string;
}

interface SpaceScope {
  machine?: { id: string; name: string } | null;
}

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

export interface SettingsRouteViewProps {
  // Data
  bootstrap: BootstrapInfo;
  currentSpaceScope: SpaceScope | null;
  dependencyCheck: RuntimeCapabilities | null;
  settings: DesktopSettings;
  terminalPresets: TerminalPresetRecord[];

  // Settings section state
  selectedSettingsSection: SettingsSection;
  onSelectSettingsSection: (section: SettingsSection) => void;

  // Status
  statusMessage: string | null;
  isSavingDeviceName: boolean;
  didCopyDeviceId: boolean;
  deviceNameDraft: string;

  // Handlers
  onBack: () => void;
  onSettingsSubmit: (event: FormEvent) => void;
  onDeviceNameSubmit: (event: FormEvent) => void;
  onCopyDeviceId: () => void;
  onSettingsChange: (patch: Partial<DesktopSettings>) => void;
  onApplySettingsPatch: (patch: Partial<DesktopSettings>) => void;
  onDeviceNameDraftChange: (value: string) => void;
  onAddTerminalPreset: () => void;
  onSaveTerminalPresets: () => void;
  onTerminalPresetChange: (
    presetId: string,
    patch: Partial<TerminalPresetRecord>,
  ) => void;
  onDeleteTerminalPreset: (presetId: string) => void;
  onTerminalPresetProviderChange: (presetId: string, value: string) => void;

  // Options builders
  desktopPreferredViewOptions: Array<SelectOption<string>>;
  preferredViewSelectValue: (view: string | null | undefined) => string;
  buildIssueRuntimeProviderOptions: (
    check: RuntimeCapabilities | null,
    command: string,
    model: string,
  ) => Array<SelectOption<string>>;
  buildAgentModelOptions: (
    preset: TerminalPresetRecord,
    check: RuntimeCapabilities | null,
  ) => string[];
  mergeIssueOptions: (defaults: string[], selected: string) => string[];
  detectAgentCliProvider: (command: string, model: string) => string;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const themeModes: ThemeMode[] = ["system", "light", "dark"];
const fontSizePresets: FontSizePreset[] = ["small", "medium", "large"];

const settingsSectionGroups: Array<{
  title: string;
  sections: Array<{ id: SettingsSection; label: string }>;
}> = [
  {
    title: "App",
    sections: [
      { id: "appearance", label: "Appearance" },
      { id: "notifications", label: "Notifications" },
      { id: "privacy", label: "Privacy" },
    ],
  },
  {
    title: "Device",
    sections: [{ id: "about", label: "About" }],
  },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sectionIcon(section: SettingsSection): ReactNode {
  switch (section) {
    case "appearance":
      return <PaletteIcon className="size-4" />;
    case "notifications":
      return <BellIcon className="size-4" />;
    case "privacy":
      return <ShieldIcon className="size-4" />;
    case "about":
      return <LaptopIcon className="size-4" />;
  }
}

function capitalize(value: string) {
  return value.slice(0, 1).toUpperCase() + value.slice(1);
}

function fontSizePresetDescription(preset: FontSizePreset) {
  switch (preset) {
    case "small":
      return "Compact interface";
    case "medium":
      return "Default size";
    case "large":
      return "Larger text and UI";
  }
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function SettingsRouteView(props: SettingsRouteViewProps) {
  const {
    bootstrap,
    currentSpaceScope,
    dependencyCheck,
    settings,
    terminalPresets,
    selectedSettingsSection,
    onSelectSettingsSection,
    statusMessage,
    isSavingDeviceName,
    didCopyDeviceId,
    deviceNameDraft,
    onBack,
    onSettingsSubmit,
    onDeviceNameSubmit,
    onCopyDeviceId,
    onSettingsChange,
    onApplySettingsPatch,
    onDeviceNameDraftChange,
    onAddTerminalPreset,
    onSaveTerminalPresets,
    onTerminalPresetChange,
    onDeleteTerminalPreset,
    onTerminalPresetProviderChange,
    desktopPreferredViewOptions,
    preferredViewSelectValue,
    buildIssueRuntimeProviderOptions,
    buildAgentModelOptions,
    mergeIssueOptions,
    detectAgentCliProvider,
  } = props;

  return (
    <SidebarProvider
      className="min-h-0 flex-1"
      style={
        {
          "--sidebar-width": "16rem",
          "--sidebar-width-icon": "16rem",
        } as React.CSSProperties
      }
    >
      <SettingsSidebar
        onBack={onBack}
        onSelectSection={onSelectSettingsSection}
        selectedSection={selectedSettingsSection}
      />
      <SidebarInset className="overflow-y-auto">
        <div className="mx-auto w-full max-w-2xl px-6 py-8">
          {statusMessage ? (
            <div className="mb-4 rounded-lg border border-border bg-muted px-4 py-2 text-sm text-muted-foreground">
              {statusMessage}
            </div>
          ) : null}

          {selectedSettingsSection === "appearance" ? (
            <AppearanceSection
              desktopPreferredViewOptions={desktopPreferredViewOptions}
              onApplySettingsPatch={onApplySettingsPatch}
              onSettingsChange={onSettingsChange}
              onSettingsSubmit={onSettingsSubmit}
              preferredViewSelectValue={preferredViewSelectValue}
              settings={settings}
            />
          ) : null}

          {selectedSettingsSection === "notifications" ? (
            <PageShell
              subtitle="This feature is coming soon."
              title="Notifications"
            >
              <p className="text-sm text-muted-foreground">
                Settings for notifications will appear here.
              </p>
            </PageShell>
          ) : null}

          {selectedSettingsSection === "privacy" ? (
            <PrivacySection bootstrap={bootstrap} />
          ) : null}

          {selectedSettingsSection === "about" ? (
            <AboutSection
              buildAgentModelOptions={buildAgentModelOptions}
              buildIssueRuntimeProviderOptions={
                buildIssueRuntimeProviderOptions
              }
              currentSpaceScope={currentSpaceScope}
              dependencyCheck={dependencyCheck}
              detectAgentCliProvider={detectAgentCliProvider}
              deviceNameDraft={deviceNameDraft}
              didCopyDeviceId={didCopyDeviceId}
              isSavingDeviceName={isSavingDeviceName}
              mergeIssueOptions={mergeIssueOptions}
              onAddTerminalPreset={onAddTerminalPreset}
              onCopyDeviceId={onCopyDeviceId}
              onDeleteTerminalPreset={onDeleteTerminalPreset}
              onDeviceNameDraftChange={onDeviceNameDraftChange}
              onDeviceNameSubmit={onDeviceNameSubmit}
              onSaveTerminalPresets={onSaveTerminalPresets}
              onTerminalPresetChange={onTerminalPresetChange}
              onTerminalPresetProviderChange={onTerminalPresetProviderChange}
              terminalPresets={terminalPresets}
            />
          ) : null}
        </div>
      </SidebarInset>
    </SidebarProvider>
  );
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

function SettingsSidebar({
  onBack,
  onSelectSection,
  selectedSection,
}: {
  onBack: () => void;
  onSelectSection: (section: SettingsSection) => void;
  selectedSection: SettingsSection;
}) {
  return (
    <Sidebar collapsible="none" className="border-r">
      <SidebarHeader className="px-4 py-4">
        <Button
          className="w-full justify-start"
          onClick={onBack}
          variant="ghost"
        >
          <ArrowLeftIcon className="size-4" />
          Back
        </Button>
        <div className="mt-2 px-2">
          <h2 className="text-base font-semibold">Settings</h2>
          <p className="text-xs text-muted-foreground">
            App and device preferences
          </p>
        </div>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              <SidebarMenuItem>
                <SidebarMenuButton onClick={onBack}>
                  <HomeIcon className="size-4" />
                  Home
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
        {settingsSectionGroups.map((group) => (
          <SidebarGroup key={group.title}>
            <SidebarGroupLabel>{group.title}</SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {group.sections.map((section) => (
                  <SidebarMenuItem key={section.id}>
                    <SidebarMenuButton
                      isActive={selectedSection === section.id}
                      onClick={() => onSelectSection(section.id)}
                    >
                      {sectionIcon(section.id)}
                      {section.label}
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
        ))}
      </SidebarContent>
    </Sidebar>
  );
}

// ---------------------------------------------------------------------------
// Page Shell
// ---------------------------------------------------------------------------

function PageShell({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: ReactNode;
}) {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        <p className="text-sm text-muted-foreground">{subtitle}</p>
      </div>
      <Separator />
      {children}
    </div>
  );
}

function SectionBlock({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: ReactNode;
}) {
  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium">{title}</h3>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Appearance Section
// ---------------------------------------------------------------------------

function AppearanceSection({
  settings,
  onApplySettingsPatch,
  onSettingsChange,
  onSettingsSubmit,
  desktopPreferredViewOptions,
  preferredViewSelectValue,
}: {
  settings: DesktopSettings;
  onApplySettingsPatch: (patch: Partial<DesktopSettings>) => void;
  onSettingsChange: (patch: Partial<DesktopSettings>) => void;
  onSettingsSubmit: (event: FormEvent) => void;
  desktopPreferredViewOptions: Array<SelectOption<string>>;
  preferredViewSelectValue: (view: string | null | undefined) => string;
}) {
  return (
    <PageShell
      subtitle="Customize how the app looks on your device."
      title="Appearance"
    >
      <SectionBlock
        description="Select your preferred color scheme"
        title="Theme"
      >
        <div className="grid grid-cols-3 gap-3">
          {themeModes.map((mode) => (
            <ThemeModeCard
              isAvailable={mode === "dark"}
              isSelected={(settings.theme_mode ?? "dark") === mode}
              key={mode}
              mode={mode}
              onSelect={() => onApplySettingsPatch({ theme_mode: mode })}
            />
          ))}
        </div>
      </SectionBlock>

      <SectionBlock
        description="Adjust the interface text size"
        title="Text Size"
      >
        <div className="grid grid-cols-3 gap-3">
          {fontSizePresets.map((preset) => (
            <FontSizePresetCard
              isSelected={(settings.font_size_preset ?? "medium") === preset}
              key={preset}
              onSelect={() =>
                onApplySettingsPatch({ font_size_preset: preset })
              }
              preset={preset}
            />
          ))}
        </div>
      </SectionBlock>

      <SectionBlock
        description="Local app preferences for this installation."
        title="App Behavior"
      >
        <form className="space-y-6" onSubmit={onSettingsSubmit}>
          <div className="space-y-4">
            <div className="flex items-center justify-between rounded-lg border border-border p-4">
              <div className="space-y-0.5">
                <Label>Show structured message JSON</Label>
                <p className="text-xs text-muted-foreground">
                  Expose the raw payload beneath structured session messages.
                </p>
              </div>
              <Switch
                checked={settings.show_raw_message_json}
                onCheckedChange={(checked) =>
                  onSettingsChange({ show_raw_message_json: checked })
                }
              />
            </div>

            <div className="flex items-center justify-between rounded-lg border border-border p-4">
              <div className="space-y-0.5">
                <Label>Default opening view</Label>
                <p className="text-xs text-muted-foreground">
                  Choose the first screen shown when Unbound Desktop launches.
                </p>
              </div>
              <Select
                value={preferredViewSelectValue(settings.preferred_view)}
                onValueChange={(value) =>
                  onSettingsChange({ preferred_view: value })
                }
              >
                <SelectTrigger className="w-[160px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {desktopPreferredViewOptions.map((option) => (
                    <SelectItem key={option.value} value={option.value}>
                      {option.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="flex justify-end">
            <Button type="submit">Save app settings</Button>
          </div>
        </form>
      </SectionBlock>
    </PageShell>
  );
}

// ---------------------------------------------------------------------------
// Theme Mode Card
// ---------------------------------------------------------------------------

function ThemeModeCard({
  mode,
  isSelected,
  isAvailable,
  onSelect,
}: {
  mode: ThemeMode;
  isSelected: boolean;
  isAvailable: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      className={cn(
        "flex flex-col items-center gap-2 rounded-lg border-2 p-3 text-center transition-colors",
        isSelected
          ? "border-primary bg-primary/5"
          : "border-border hover:border-muted-foreground/30",
        !isAvailable && "cursor-not-allowed opacity-50",
      )}
      disabled={!isAvailable}
      onClick={onSelect}
      type="button"
    >
      <ThemePreview
        isAvailable={isAvailable}
        isSelected={isSelected}
        mode={mode}
      />
      <span className="text-sm font-medium">{capitalize(mode)}</span>
      {isAvailable ? (
        isSelected ? (
          <CheckIcon className="size-4 text-primary" />
        ) : (
          <span className="h-4" />
        )
      ) : (
        <span className="text-xs text-muted-foreground">Coming soon</span>
      )}
    </button>
  );
}

function ThemePreview({
  mode,
  isSelected,
  isAvailable,
}: {
  mode: ThemeMode;
  isSelected: boolean;
  isAvailable: boolean;
}) {
  const isDark = mode !== "light";

  return (
    <div
      className={cn(
        "flex h-16 w-full overflow-hidden rounded-md border",
        isDark ? "bg-zinc-900" : "bg-zinc-100",
        isSelected && "ring-1 ring-primary",
        !isAvailable && "opacity-60",
      )}
    >
      <div
        className={cn(
          "flex w-1/4 flex-col gap-1 p-1.5",
          isDark ? "bg-zinc-800" : "bg-zinc-200",
        )}
      >
        <div
          className={cn(
            "h-1.5 w-full rounded-sm",
            isDark ? "bg-zinc-700" : "bg-zinc-300",
          )}
        />
        <div
          className={cn(
            "h-1.5 w-3/4 rounded-sm",
            isDark ? "bg-zinc-700" : "bg-zinc-300",
          )}
        />
        <div
          className={cn(
            "h-1.5 w-1/2 rounded-sm",
            isDark ? "bg-zinc-700" : "bg-zinc-300",
          )}
        />
      </div>
      <div className="flex flex-1 flex-col gap-1 p-1.5">
        <div
          className={cn(
            "h-2 w-3/4 rounded-sm",
            isDark ? "bg-zinc-700" : "bg-zinc-300",
          )}
        />
        <div
          className={cn(
            "h-2 w-1/2 rounded-sm",
            isDark ? "bg-zinc-800" : "bg-zinc-200",
          )}
        />
        <div
          className={cn(
            "h-2 w-2/3 rounded-sm",
            isDark ? "bg-zinc-800" : "bg-zinc-200",
          )}
        />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Font Size Preset Card
// ---------------------------------------------------------------------------

function FontSizePresetCard({
  preset,
  isSelected,
  onSelect,
}: {
  preset: FontSizePreset;
  isSelected: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      className={cn(
        "flex flex-col items-center gap-2 rounded-lg border-2 p-3 text-center transition-colors",
        isSelected
          ? "border-primary bg-primary/5"
          : "border-border hover:border-muted-foreground/30",
      )}
      onClick={onSelect}
      type="button"
    >
      <FontSizePreview preset={preset} />
      <span className="text-sm font-medium">{capitalize(preset)}</span>
      <span className="text-xs text-muted-foreground">
        {fontSizePresetDescription(preset)}
      </span>
      {isSelected ? (
        <CheckIcon className="size-4 text-primary" />
      ) : (
        <span className="h-4" />
      )}
    </button>
  );
}

function FontSizePreview({ preset }: { preset: FontSizePreset }) {
  const scale =
    preset === "small" ? "text-xs" : preset === "large" ? "text-lg" : "text-sm";
  return (
    <div className="flex h-12 w-full items-center justify-center rounded-md border bg-muted/50">
      <span className={cn("font-semibold text-muted-foreground", scale)}>
        Aa
      </span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Privacy Section
// ---------------------------------------------------------------------------

function PrivacySection({ bootstrap }: { bootstrap: BootstrapInfo }) {
  return (
    <PageShell
      subtitle="Your data is protected with end-to-end encryption."
      title="Privacy"
    >
      <SectionBlock
        description="Runtime information and local storage boundaries."
        title="Daemon Runtime"
      >
        <Card>
          <CardContent className="space-y-3">
            <DetailRow
              label="App version"
              value={bootstrap.expected_app_version}
            />
            <DetailRow
              label="Daemon version"
              value={bootstrap.daemon_info?.daemon_version ?? "N/A"}
            />
            <DetailRow label="Socket" value={bootstrap.socket_path} />
            <DetailRow label="Base dir" value={bootstrap.base_dir} />
          </CardContent>
        </Card>
      </SectionBlock>
    </PageShell>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-mono text-xs">{value}</span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// About Section
// ---------------------------------------------------------------------------

function AboutSection({
  currentSpaceScope,
  dependencyCheck,
  terminalPresets,
  isSavingDeviceName,
  didCopyDeviceId,
  deviceNameDraft,
  onDeviceNameSubmit,
  onCopyDeviceId,
  onDeviceNameDraftChange,
  onAddTerminalPreset,
  onSaveTerminalPresets,
  onTerminalPresetChange,
  onDeleteTerminalPreset,
  onTerminalPresetProviderChange,
  buildIssueRuntimeProviderOptions,
  buildAgentModelOptions,
  mergeIssueOptions,
  detectAgentCliProvider,
}: {
  currentSpaceScope: SpaceScope | null;
  dependencyCheck: RuntimeCapabilities | null;
  terminalPresets: TerminalPresetRecord[];
  isSavingDeviceName: boolean;
  didCopyDeviceId: boolean;
  deviceNameDraft: string;
  onDeviceNameSubmit: (event: FormEvent) => void;
  onCopyDeviceId: () => void;
  onDeviceNameDraftChange: (value: string) => void;
  onAddTerminalPreset: () => void;
  onSaveTerminalPresets: () => void;
  onTerminalPresetChange: (
    presetId: string,
    patch: Partial<TerminalPresetRecord>,
  ) => void;
  onDeleteTerminalPreset: (presetId: string) => void;
  onTerminalPresetProviderChange: (presetId: string, value: string) => void;
  buildIssueRuntimeProviderOptions: (
    check: RuntimeCapabilities | null,
    command: string,
    model: string,
  ) => Array<SelectOption<string>>;
  buildAgentModelOptions: (
    preset: TerminalPresetRecord,
    check: RuntimeCapabilities | null,
  ) => string[];
  mergeIssueOptions: (defaults: string[], selected: string) => string[];
  detectAgentCliProvider: (command: string, model: string) => string;
}) {
  return (
    <PageShell subtitle="Manage identity for this device." title="About">
      <SectionBlock
        description="Name this device and review the identifier used by the daemon."
        title="Device"
      >
        <Card>
          <form onSubmit={onDeviceNameSubmit}>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="device-name">Device name</Label>
                <p className="text-xs text-muted-foreground">
                  This name appears anywhere this machine is referenced in the
                  app.
                </p>
                <Input
                  id="device-name"
                  onChange={(event) =>
                    onDeviceNameDraftChange(event.target.value)
                  }
                  placeholder="This Device"
                  value={deviceNameDraft}
                />
              </div>

              <div className="space-y-2">
                <Label>Device ID</Label>
                <p className="text-xs text-muted-foreground">
                  This identifier is generated for the current device and cannot
                  be edited.
                </p>
                <div className="flex gap-2">
                  <Input
                    className="flex-1 font-mono text-xs"
                    readOnly
                    value={currentSpaceScope?.machine?.id ?? ""}
                  />
                  <Button
                    onClick={onCopyDeviceId}
                    size="default"
                    type="button"
                    variant="outline"
                  >
                    {didCopyDeviceId ? (
                      <CheckIcon className="size-4" />
                    ) : (
                      <CopyIcon className="size-4" />
                    )}
                    {didCopyDeviceId ? "Copied" : "Copy"}
                  </Button>
                </div>
              </div>
            </CardContent>
            <CardFooter className="justify-end">
              <Button disabled={isSavingDeviceName} type="submit">
                {isSavingDeviceName ? "Saving..." : "Save device name"}
              </Button>
            </CardFooter>
          </form>
        </Card>
      </SectionBlock>

      <SectionBlock
        description="Save reusable Claude and Codex launch configurations so new tasks can start from a preset."
        title="Terminal Presets"
      >
        <div className="space-y-4">
          {terminalPresets.length > 0 ? (
            terminalPresets.map((preset) => (
              <TerminalPresetEditor
                buildAgentModelOptions={buildAgentModelOptions}
                buildIssueRuntimeProviderOptions={
                  buildIssueRuntimeProviderOptions
                }
                dependencyCheck={dependencyCheck}
                detectAgentCliProvider={detectAgentCliProvider}
                key={preset.id}
                mergeIssueOptions={mergeIssueOptions}
                onChange={(patch) => onTerminalPresetChange(preset.id, patch)}
                onDelete={() => onDeleteTerminalPreset(preset.id)}
                onProviderChange={(value) =>
                  onTerminalPresetProviderChange(preset.id, value)
                }
                preset={preset}
              />
            ))
          ) : (
            <Card>
              <CardContent className="py-8 text-center">
                <h3 className="text-sm font-medium">No presets yet</h3>
                <p className="mt-1 text-sm text-muted-foreground">
                  Add a preset for your common Claude or Codex setup, including
                  model, plan mode, and extra flags.
                </p>
              </CardContent>
            </Card>
          )}

          <div className="flex gap-2 justify-end">
            <Button
              onClick={onAddTerminalPreset}
              type="button"
              variant="outline"
            >
              <PlusIcon className="size-4" />
              Add preset
            </Button>
            <Button onClick={onSaveTerminalPresets} type="button">
              Save presets
            </Button>
          </div>
        </div>
      </SectionBlock>
    </PageShell>
  );
}

// ---------------------------------------------------------------------------
// Terminal Preset Editor
// ---------------------------------------------------------------------------

function TerminalPresetEditor({
  dependencyCheck,
  onChange,
  onDelete,
  onProviderChange,
  preset,
  buildIssueRuntimeProviderOptions,
  buildAgentModelOptions,
  mergeIssueOptions,
  detectAgentCliProvider,
}: {
  dependencyCheck: RuntimeCapabilities | null;
  onChange: (patch: Partial<TerminalPresetRecord>) => void;
  onDelete: () => void;
  onProviderChange: (value: string) => void;
  preset: TerminalPresetRecord;
  buildIssueRuntimeProviderOptions: (
    check: RuntimeCapabilities | null,
    command: string,
    model: string,
  ) => Array<SelectOption<string>>;
  buildAgentModelOptions: (
    preset: TerminalPresetRecord,
    check: RuntimeCapabilities | null,
  ) => string[];
  mergeIssueOptions: (defaults: string[], selected: string) => string[];
  detectAgentCliProvider: (command: string, model: string) => string;
}) {
  const provider = detectAgentCliProvider(preset.command, preset.model);
  const providerOptions = buildIssueRuntimeProviderOptions(
    dependencyCheck,
    preset.command,
    preset.model,
  );
  const modelOptions = buildAgentModelOptions(preset, dependencyCheck);
  const thinkingEffortOptions = mergeIssueOptions(
    ["auto", "low", "medium", "high"],
    preset.thinkingEffort,
  );
  const browserToggleLabel =
    provider === "codex" ? "Enable web search" : "Enable Chrome";
  const browserToggleDescription =
    provider === "codex"
      ? "Expose Codex web search when tasks use this preset."
      : "Allow browser automation when tasks use this preset.";

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>{preset.name || "Terminal preset"}</CardTitle>
            <CardDescription>
              {provider === "codex"
                ? "Codex runtime preset"
                : "Claude runtime preset"}
            </CardDescription>
          </div>
          <Button
            onClick={onDelete}
            size="sm"
            type="button"
            variant="destructive"
          >
            <Trash2Icon className="size-4" />
            Delete
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label htmlFor={`preset-name-${preset.id}`}>Name</Label>
            <Input
              id={`preset-name-${preset.id}`}
              onChange={(event) => onChange({ name: event.target.value })}
              placeholder="Claude review preset"
              value={preset.name}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor={`preset-provider-${preset.id}`}>Provider</Label>
            <select
              aria-label="Terminal preset provider"
              className="flex h-8 w-full items-center rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30"
              id={`preset-provider-${preset.id}`}
              onChange={(event) => onProviderChange(event.target.value)}
              value={preset.command}
            >
              {providerOptions.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <Label htmlFor={`preset-command-${preset.id}`}>Command</Label>
            <Input
              id={`preset-command-${preset.id}`}
              onChange={(event) => onChange({ command: event.target.value })}
              placeholder="claude"
              value={preset.command}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor={`preset-model-${preset.id}`}>Model</Label>
            <select
              aria-label="Terminal preset model"
              className="flex h-8 w-full items-center rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30"
              id={`preset-model-${preset.id}`}
              onChange={(event) => onChange({ model: event.target.value })}
              value={preset.model}
            >
              {modelOptions.map((option) => (
                <option key={option} value={option}>
                  {option === "default" ? "Default" : option}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <Label htmlFor={`preset-thinking-${preset.id}`}>
              Thinking effort
            </Label>
            <select
              aria-label="Terminal preset thinking effort"
              className="flex h-8 w-full items-center rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30"
              id={`preset-thinking-${preset.id}`}
              onChange={(event) =>
                onChange({ thinkingEffort: event.target.value })
              }
              value={preset.thinkingEffort}
            >
              {thinkingEffortOptions.map((option) => (
                <option key={option} value={option}>
                  {capitalize(option)}
                </option>
              ))}
            </select>
          </div>

          <div className="col-span-2 space-y-2">
            <Label htmlFor={`preset-extra-${preset.id}`}>Extra flags</Label>
            <Input
              id={`preset-extra-${preset.id}`}
              onChange={(event) => onChange({ extraArgs: event.target.value })}
              placeholder="--verbose, --dangerously-skip-permissions"
              value={preset.extraArgs}
            />
          </div>
        </div>

        <Separator />

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div className="flex items-center justify-between rounded-lg border border-border p-3">
            <div className="space-y-0.5">
              <Label className="text-xs">Plan mode</Label>
              <p className="text-[11px] text-muted-foreground">
                Enable Claude plan mode when this preset is selected.
              </p>
            </div>
            <Switch
              checked={preset.planMode}
              onCheckedChange={(checked) => onChange({ planMode: checked })}
              size="sm"
            />
          </div>
          <div className="flex items-center justify-between rounded-lg border border-border p-3">
            <div className="space-y-0.5">
              <Label className="text-xs">{browserToggleLabel}</Label>
              <p className="text-[11px] text-muted-foreground">
                {browserToggleDescription}
              </p>
            </div>
            <Switch
              checked={preset.enableChrome}
              onCheckedChange={(checked) => onChange({ enableChrome: checked })}
              size="sm"
            />
          </div>
          <div className="flex items-center justify-between rounded-lg border border-border p-3">
            <div className="space-y-0.5">
              <Label className="text-xs">Skip permissions</Label>
              <p className="text-[11px] text-muted-foreground">
                Skip interactive permission prompts when this preset is
                selected.
              </p>
            </div>
            <Switch
              checked={preset.skipPermissions}
              onCheckedChange={(checked) =>
                onChange({ skipPermissions: checked })
              }
              size="sm"
            />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
