import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { registerDestructor } from "@ember/destroyable";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dPointerDrag from "discourse/ui-kit/modifiers/d-pointer-drag";
import { i18n } from "discourse-i18n";

const DRAG_RESISTANCE = 0.28;
const FLICK_PROJECTION_SECONDS = 0.18;
const MAX_MOBILE_TOPICS = 3;
const MIN_FLICK_VELOCITY = 600;
const SPRING_DAMPING = 24;
const SPRING_STIFFNESS = 210;

export default class FeaturedHomepageTopicsCarousel extends Component {
  @service a11y;
  @service capabilities;

  @tracked currentPosition = 0;
  @tracked dragOffset = 0;
  @tracked isSettling = false;

  #animationFrame;
  #dragStartPosition = 0;
  #lastPointerTime = 0;
  #lastPointerX = 0;
  #pointerVelocity = 0;
  #suppressClickUntil = 0;
  #viewportWidth = 1;

  constructor() {
    super(...arguments);
    registerDestructor(this, () => this.#cancelSpring());
  }

  get topics() {
    return this.args.topics ?? [];
  }

  get enabled() {
    return this.args.enabled && !this.capabilities.viewport.sm;
  }

  get mobileTopicCount() {
    return Math.min(MAX_MOBILE_TOPICS, this.topics.length);
  }

  get maxPosition() {
    return Math.max(0, this.mobileTopicCount - 1);
  }

  get position() {
    return Math.min(this.currentPosition, this.maxPosition);
  }

  get isRtl() {
    return document.documentElement.dir === "rtl";
  }

  get positionLabel() {
    return i18n(themePrefix("featured_topics_carousel_position"), {
      current: this.mobileTopicCount ? this.position + 1 : 0,
      total: this.mobileTopicCount,
    });
  }

  get positionDots() {
    return Array.from({ length: this.mobileTopicCount }, (_topic, index) => ({
      id: `topic-${index}`,
      isActive: index === this.position,
    }));
  }

  get trackStyle() {
    const offset = this.position * 100 * (this.isRtl ? 1 : -1);

    return trustHTML(
      `--featured-topics-carousel-offset: ${offset}%; ` +
        `--featured-topics-carousel-drag-offset: ${this.dragOffset}px;`
    );
  }

  announcePosition() {
    this.a11y.announce(this.positionLabel);
  }

  moveTo(position) {
    const nextPosition = Math.min(this.maxPosition, Math.max(0, position));
    if (nextPosition === this.position) {
      return;
    }

    this.#cancelSpring();
    this.dragOffset = 0;
    this.isSettling = false;
    this.currentPosition = nextPosition;
    this.announcePosition();
  }

  @action
  onKeydown(event) {
    if (!this.enabled) {
      return;
    }

    let nextPosition;

    switch (event.key) {
      case "ArrowLeft":
        nextPosition = this.position + (this.isRtl ? 1 : -1);
        break;
      case "ArrowRight":
        nextPosition = this.position + (this.isRtl ? -1 : 1);
        break;
      case "Home":
        nextPosition = 0;
        break;
      case "End":
        nextPosition = this.maxPosition;
        break;
      default:
        return;
    }

    event.preventDefault();
    this.moveTo(nextPosition);
  }

  @action
  onDragStart(event) {
    if (!this.enabled || this.maxPosition === 0) {
      return false;
    }

    this.#cancelSpring();
    this.currentPosition = this.position;
    this.dragOffset = 0;
    this.isSettling = false;
    this.#dragStartPosition = this.position;
    this.#lastPointerX = event.clientX;
    this.#lastPointerTime = event.timeStamp;
    this.#pointerVelocity = 0;
    this.#viewportWidth = Math.max(1, event.currentTarget.clientWidth);
  }

  @action
  onDrag(event, info) {
    let logicalDelta = info.delta.x * (this.isRtl ? 1 : -1);

    if (
      (this.#dragStartPosition === 0 && logicalDelta < 0) ||
      (this.#dragStartPosition === this.maxPosition && logicalDelta > 0)
    ) {
      logicalDelta *= DRAG_RESISTANCE;
    }

    this.dragOffset = logicalDelta * (this.isRtl ? 1 : -1);

    const elapsed = event.timeStamp - this.#lastPointerTime;
    if (elapsed > 0) {
      this.#pointerVelocity =
        ((event.clientX - this.#lastPointerX) / elapsed) * 1000;
    }
    this.#lastPointerX = event.clientX;
    this.#lastPointerTime = event.timeStamp;

    if (Math.abs(info.delta.x) > 8) {
      this.#suppressClickUntil = Date.now() + 350;
    }
  }

  @action
  onDragEnd(_event, info) {
    if (!info.moved) {
      return;
    }

    const directionFactor = this.isRtl ? 1 : -1;
    const logicalDelta = this.dragOffset * directionFactor;
    const logicalVelocity = this.#pointerVelocity * directionFactor;
    const projectedDelta =
      logicalDelta + logicalVelocity * FLICK_PROJECTION_SECONDS;
    const distanceThreshold = this.#viewportWidth * 0.2;
    let step = 0;

    if (
      projectedDelta > distanceThreshold ||
      logicalVelocity > MIN_FLICK_VELOCITY
    ) {
      step = 1;
    } else if (
      projectedDelta < -distanceThreshold ||
      logicalVelocity < -MIN_FLICK_VELOCITY
    ) {
      step = -1;
    }

    const nextPosition = Math.min(
      this.maxPosition,
      Math.max(0, this.#dragStartPosition + step)
    );
    const oldBase =
      directionFactor * this.#dragStartPosition * this.#viewportWidth;
    const newBase = directionFactor * nextPosition * this.#viewportWidth;

    this.dragOffset += oldBase - newBase;
    this.currentPosition = nextPosition;
    this.isSettling = true;
    this.#startSpring(this.#pointerVelocity);

    if (nextPosition !== this.#dragStartPosition) {
      this.announcePosition();
    }
  }

  @action
  onDragCancel() {
    this.isSettling = true;
    this.#startSpring(0);
  }

  @action
  preventDraggedClick(event) {
    if (Date.now() < this.#suppressClickUntil) {
      event.preventDefault();
      event.stopPropagation();
    }
  }

  #startSpring(initialVelocity) {
    this.#cancelSpring();

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.dragOffset = 0;
      this.isSettling = false;
      return;
    }

    let lastTime;
    let velocity = initialVelocity;

    const settle = (time) => {
      const elapsed = lastTime ? Math.min((time - lastTime) / 1000, 0.032) : 0;
      lastTime = time;

      if (elapsed > 0) {
        const acceleration =
          -SPRING_STIFFNESS * this.dragOffset - SPRING_DAMPING * velocity;
        velocity += acceleration * elapsed;
        this.dragOffset += velocity * elapsed;
      }

      if (Math.abs(this.dragOffset) < 0.5 && Math.abs(velocity) < 5) {
        this.dragOffset = 0;
        this.isSettling = false;
        this.#animationFrame = undefined;
        return;
      }

      this.#animationFrame = requestAnimationFrame(settle);
    };

    this.#animationFrame = requestAnimationFrame(settle);
  }

  #cancelSpring() {
    if (this.#animationFrame) {
      cancelAnimationFrame(this.#animationFrame);
      this.#animationFrame = undefined;
    }
  }

  <template>
    <div
      class="featured-topics-carousel"
      aria-label={{if
        this.enabled
        (i18n (themePrefix "featured_topics_carousel_label"))
      }}
      role={{if this.enabled "region"}}
    >
      <div
        class="featured-topics-carousel__viewport"
        tabindex={{if this.enabled "0"}}
        {{on "click" this.preventDraggedClick capture=true}}
        {{on "keydown" this.onKeydown}}
        {{dPointerDrag
          onDragStart=this.onDragStart
          onDrag=this.onDrag
          onDragEnd=this.onDragEnd
          onDragCancel=this.onDragCancel
          draggingClass="is-dragging"
          threshold=4
          touchAction="pan-y"
        }}
      >
        <div
          class={{dConcatClass
            "featured-topics"
            (if this.isSettling "is-settling")
          }}
          style={{this.trackStyle}}
        >
          {{#each this.topics as |topic|}}
            <div class="featured-topic">
              {{yield topic}}
            </div>
          {{/each}}
        </div>
      </div>

      {{#if this.enabled}}
        <div class="featured-topics-carousel__position">
          <span class="sr-only">{{this.positionLabel}}</span>
          {{#each this.positionDots key="id" as |dot|}}
            <span
              aria-hidden="true"
              class={{dConcatClass
                "featured-topics-carousel__position-dot"
                (if dot.isActive "is-active")
              }}
            ></span>
          {{/each}}
        </div>
      {{/if}}
    </div>
  </template>
}
