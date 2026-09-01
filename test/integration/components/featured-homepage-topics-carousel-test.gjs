import Service from "@ember/service";
import {
  find,
  findAll,
  render,
  triggerEvent,
  triggerKeyEvent,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import { stubPointerCapture } from "discourse/tests/helpers/ui-kit/pointer-gesture-helper";
import FeaturedHomepageTopicsCarousel from "../../../discourse/components/featured-homepage-topics-carousel";

const TOPICS = [
  { id: 1, title: "One" },
  { id: 2, title: "Two" },
  { id: 3, title: "Three" },
  { id: 4, title: "Four" },
];

class A11yStub extends Service {
  announce() {}
}

class MobileCapabilitiesStub extends Service {
  isIOS = false;
  viewport = { sm: false };
}

module(
  "Integration | Component | FeaturedHomepageTopicsCarousel",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      this.owner.unregister("service:a11y");
      this.owner.register("service:a11y", A11yStub);
      this.owner.unregister("service:capabilities");
      this.owner.register("service:capabilities", MobileCapabilitiesStub);
      this.topics = TOPICS;
    });

    test("mobile renders a three-topic position indicator", async function (assert) {
      await render(
        <template>
          <FeaturedHomepageTopicsCarousel
            @enabled={{true}}
            @topics={{this.topics}}
            as |topic|
          >
            <a href="/t/{{topic.id}}">{{topic.title}}</a>
          </FeaturedHomepageTopicsCarousel>
        </template>
      );

      assert
        .dom(".featured-topic")
        .exists({ count: 4 }, "all desktop topics remain in the track");
      assert
        .dom(".featured-topics-carousel__position-dot")
        .exists({ count: 3 }, "mobile navigation is limited to three topics");
      assert
        .dom(".featured-topics-carousel__position-dot.is-active")
        .exists({ count: 1 }, "only the first dot is initially active");
      assert
        .dom(".featured-topics-carousel__position .sr-only")
        .hasText("1 of 3 featured topics", "the initial position is exposed");
    });

    test("the show-all modes do not activate the carousel", async function (assert) {
      await render(
        <template>
          <FeaturedHomepageTopicsCarousel
            @enabled={{false}}
            @topics={{this.topics}}
            as |topic|
          >
            <a href="/t/{{topic.id}}">{{topic.title}}</a>
          </FeaturedHomepageTopicsCarousel>
        </template>
      );

      assert
        .dom(".featured-topics-carousel__position")
        .doesNotExist("the position indicator stays hidden");
      assert
        .dom(".featured-topics-carousel__viewport")
        .doesNotHaveAttribute("tabindex", "the static layout is not focusable");
    });

    test("dragging advances the mobile carousel", async function (assert) {
      await render(
        <template>
          <FeaturedHomepageTopicsCarousel
            @enabled={{true}}
            @topics={{this.topics}}
            as |topic|
          >
            <a href="/t/{{topic.id}}">{{topic.title}}</a>
          </FeaturedHomepageTopicsCarousel>
        </template>
      );

      const viewport = find(".featured-topics-carousel__viewport");
      Object.defineProperty(viewport, "clientWidth", { value: 300 });
      stubPointerCapture(viewport);

      await triggerEvent(viewport, "pointerdown", {
        button: 0,
        pointerId: 1,
        clientX: 250,
      });
      await triggerEvent(viewport, "pointermove", {
        pointerId: 1,
        clientX: 50,
      });
      await triggerEvent(viewport, "pointerup", {
        pointerId: 1,
        clientX: 50,
      });

      assert
        .dom(".featured-topics-carousel__position .sr-only")
        .hasText("2 of 3 featured topics", "the drag advances one topic");
      assert
        .dom(findAll(".featured-topics-carousel__position-dot")[1])
        .hasClass("is-active", "the second dot becomes active");
    });

    test("keyboard navigation stays within the three mobile topics", async function (assert) {
      await render(
        <template>
          <FeaturedHomepageTopicsCarousel
            @enabled={{true}}
            @topics={{this.topics}}
            as |topic|
          >
            <a href="/t/{{topic.id}}">{{topic.title}}</a>
          </FeaturedHomepageTopicsCarousel>
        </template>
      );

      await triggerKeyEvent(
        ".featured-topics-carousel__viewport",
        "keydown",
        "End"
      );
      assert
        .dom(".featured-topics-carousel__position .sr-only")
        .hasText("3 of 3 featured topics", "End moves to the third topic");

      await triggerKeyEvent(
        ".featured-topics-carousel__viewport",
        "keydown",
        "Home"
      );
      assert
        .dom(".featured-topics-carousel__position .sr-only")
        .hasText("1 of 3 featured topics", "Home returns to the first topic");
    });
  }
);
