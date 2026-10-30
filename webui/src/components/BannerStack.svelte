<!--
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
-->

<script>
  import { fly } from "svelte/transition";
  import { flip } from "svelte/animate";
  import { cubicOut } from "svelte/easing";
  import { banner } from "../stores/banner.svelte.js";
  import { toast } from "../stores/toast.svelte.js";

  let height = $state(0);
  let items = $derived([...banner.items].sort((a, b) => a.order - b.order));

  $effect(() => {
    toast.setBannerOffset(height);
  });

  function flyOut(node, { y = 100, duration = 300, easing = cubicOut } = {}) {
    const stack = node.offsetParent;
    const bottom = stack.clientHeight - node.offsetTop - node.offsetHeight;
    node.style.position = "absolute";
    node.style.left = "0";
    node.style.right = "0";
    node.style.bottom = `${bottom}px`;
    return {
      duration,
      easing,
      css: (t, u) => `transform: translateY(${u * y}px); opacity: ${t};`,
    };
  }
</script>

<div class="banner-stack" bind:clientHeight={height}>
  {#each items as b (b.id)}
    <div
      id="{b.id}-banner"
      class="notification-banner"
      class:pulse={b.pulse}
      in:fly={{ y: 100, duration: 300, easing: cubicOut }}
      out:flyOut
      animate:flip={{ duration: 300, easing: cubicOut }}
    >
      <div class="notification-content">
        {#if b.icon === "spinner"}
          <span class="m3-spinner"></span>
        {:else if b.icon === "warning"}
          <IMaterialSymbolsWarning class="mi-icon" />
        {:else if b.icon === "restart"}
          <IMaterialSymbolsRestartAlt class="mi-icon" />
        {/if}
        <span class="notification-text">{b.text}</span>
      </div>
      {#if b.actionLabel}
        <button
          class="m3-btn btn-notification-action"
          onclick={b.onAction}
          disabled={b.actionDisabled ? b.actionDisabled() : false}
        >
          {b.actionLabel}
        </button>
      {/if}
    </div>
  {/each}
</div>
