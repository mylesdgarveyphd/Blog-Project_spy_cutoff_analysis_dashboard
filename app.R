# Install and load required libraries if not installed
# install.packages(c("shiny", "shinydashboard", "plotly"))

library(shiny)
library(shinydashboard)
library(plotly)
library(tidyverse)

# Intro: Load in the SPY stock return dataset
spy_data_org <- read.csv("spy.csv") %>% 
  as_tibble() %>%
  arrange(date) %>%
  mutate(id = row_number())  # Create a new column "id"

# UI
ui <- dashboardPage(
  dashboardHeader(title = "SPY Time Study"),
  dashboardSidebar(
    tags$head(
      tags$style(
        HTML("
          .sidebar-menu li a span {
            white-space: normal !important;
          }
          .skin-red-light .main-header, .skin-red-light .main-sidebar, .skin-red-light .main-content {
            background-color: #f2dede;
          }
          
          .skin-red-light .main-header .logo, .skin-red-light .main-header .navbar .sidebar-toggle {
            background-color: #d9534f;
          }
          
          .skin-red-light .main-header .logo:hover, .skin-red-light .main-header .navbar .sidebar-toggle:hover {
            background-color: #c9302c;
          }
          
          .skin-red-light .main-sidebar .sidebar-menu a {
            color: #2c3e50;
          }
          
          .skin-red-light .main-sidebar .sidebar-menu a:hover {
            background: #d9534f;
            color: #fff;
          }
          
          .skin-red-light .main-sidebar .treeview-menu > li > a {
            color: #34495e;
          }
          
          .skin-red-light .main-sidebar .treeview-menu > li.active > a {
            background: #d9534f;
          }
        ")
      )
    ),
    sidebarMenu(
      id = "tabs",
      menuItem("Introduction to This Study", tabName = "tabintro"),
      menuItem("(1) Defining an \"Abnormal Event\"", tabName = "tab1"),
      menuItem("(2) Exploring The Times Since Last Abnormal Events", tabName = "tab2"),
      menuItem("(3) Exploring The Time Differences Between Abnormal Events", tabName = "tab3"),
      menuItem("(4) Studying the Relationship between Previous and Current Time Differences Between Abnormal Events", tabName = "tab4"),
      menuItem("(5) Studying Time Differences between Abnormal Events in Different Time Periods", tabName = "tab5")
    ),
    sliderInput("cutoff_input", "Abnormal Threshold:", value = 0.05, step = 0.005, min = 0, max = 0.1),
    dateRangeInput("date_range", "Select Date Range",start="2000-01-01",end="2024-01-05"),
    
    conditionalPanel(
      condition = "input.tabs != 'tab1'",
      checkboxInput("split_checkbox", "Split"),
      sliderInput("max_days", "Max Days:", min = 0, max = 1500, value =720, step = 10)
    ),
    conditionalPanel(
      condition = "input.tabs == 'tab4'",
      sliderInput("lag_slider", "Lag:", min = 0, max = 10, value = 1),
      checkboxInput("log_checkbox", "Log Scale")
    )
  ),
  dashboardBody(
    tabItems(
      tabItem(
        tabName = "tabintro",
        h2("Introduction"),
        p("This is an introduction to the current study at hand.")
      ),
      tabItem(
        tabName = "tab1",
        h2("Step (1): Defining an \"Abnormal Event\""),
        p("Tab 1 Paragraph Text"),
        plotlyOutput("p1"),
        plotlyOutput("p2"),
        dataTableOutput("pos_neg_table")
      ),
      tabItem(
        tabName = "tab2",
        h2("Step (2): Exploring The Times Since Last Abnormal Events"),
        p("Tab 2 Paragraph Text"),
        plotlyOutput("p2_1"),
        plotlyOutput("p2_2"),
        plotlyOutput("p2_3")
      ),
      tabItem(
        tabName = "tab3",
        h2("Step (3): Exploring The Time Differences Between Abnormal Events"),
        p("Tab 3 Paragraph Text"),
        plotlyOutput("p3_1"),
        plotlyOutput("p3_2"),
        plotlyOutput("p3_3")
      ),
      tabItem(
        tabName = "tab4",
        h2("Step (4): Studying the Relationship between Previous and Current Time Differences Between Abnormal Events "),
        p("Tab 4 Paragraph Text"),
        plotlyOutput("p4_1"),
        plotlyOutput("p4_2")
      )
    )
  )
)

server <- function(input, output) {
  # Define reactive expression for filtered data based on user input
  spy_data <- reactive({
    ################################################################
    # Step (0) Some Data Wrangling
    ################################################################
    # Default lower and upper bounds
    lower_bound <- -1*input$cutoff_input
    upper_bound <- input$cutoff_input
    
    # We will first define a "threshold" to use to determine if a stock return
    # is "abnormal" or "typical":
    cut_points <- c(lower_bound, upper_bound)
    
    # Now we will create a new column called "event_type" that will be used
    # to indicate if the current observation experienced a percentage return
    # that was greater than (or less than) the threshold
    # Create "event_type" column
    spy_data <- spy_data_org %>%
      mutate(
        event_type = ifelse(per_chg_from_day_prior < lower_bound, -1,
                            ifelse(per_chg_from_day_prior > upper_bound, 1, 0))
      )
    
    # Now compute the "days since," which is the number of trading days
    # since the last time the stock had a "negative" or "positive" event,
    # where "event" is defined as the closing price surpassing the threshold
    # defined earlier in step (2):
    spy_data <- spy_data %>%
      arrange(id) %>%
      mutate(
        last_neg_id = ifelse(event_type == -1, id, NA),
        last_pos_id = ifelse(event_type == 1, id, NA)
      ) %>%
      fill(last_neg_id, last_pos_id, .direction = "down")
    
    spy_data <- spy_data %>%
      mutate(
        num_obs_since_last_neg = row_number() - last_neg_id,
        num_obs_since_last_pos = ifelse(is.na(last_pos_id), NA, row_number() - last_pos_id)
      ) %>%
      select(-last_neg_id, -last_pos_id)
    
    # Filter the data by date.
    start_date <- as.Date(input$date_range[1])
    end_date <- as.Date(input$date_range[2])
    
    spy_data <- spy_data %>%
      filter(between(as.Date(date), start_date, end_date))
    
    spy_data
  })
  
  # Define reactive expression for time difference data
  time_diff_data <- reactive({
    time_diff_neg_data <- spy_data() %>%
      filter(event_type == -1) %>%
      mutate(time_diff = id - lag(id)) %>%
      mutate(type = "Negative")
    
    time_diff_pos_data <- spy_data() %>%
      filter(event_type == 1) %>%
      mutate(time_diff = id - lag(id)) %>%
      mutate(type = "Positive")
    
    time_diff_data <- bind_rows(time_diff_neg_data, time_diff_pos_data) %>%
      filter(between(as.Date(date), input$date_range[1], input$date_range[2]))%>%
      filter(time_diff < input$max_days)
    
    time_diff_data
  })
  
  #Define reactive expression for lagged time difference
  time_diff_lag<-reactive({
    ################################################################
    #Step (4) Predicting Time Differences (Can past time differences impact future?)
    ################################################################
    lag_n<-input$lag_slider
    log_scale<-input$log_checkbox
    
    #Compute the lags
    tdn<-time_diff_data()%>%
      filter(event_type == -1)%>%
      mutate(time_diff_before = lag(time_diff,lag_n))%>%
      drop_na(time_diff_before)
    
    tdp<-time_diff_data()%>%
      filter(event_type == 1)%>%
      mutate(time_diff_before = lag(time_diff,lag_n))%>%
      drop_na(time_diff_before)
    
    time_diff_lag<-
      tdn%>%
      union_all(tdp)
    
    rm(tdn)
    rm(tdp)
    
    time_diff_lag
  })
  
  spy_data2<-reactive({
    data<-spy_data() %>%
      gather(num_obs_since_last_neg:num_obs_since_last_pos,key="type",value="num_since")%>%
      drop_na(num_since)%>%
      filter(num_since < input$max_days)
    data
  })
  
  # Define reactive plots based on user inputs
  output$p1 <- renderPlotly({
    lower_bound <- -1*input$cutoff_input
    upper_bound <- input$cutoff_input
    
    density_data <- density(spy_data()$per_chg_from_day_prior)
    p1 <- ggplot(spy_data(), aes(x = per_chg_from_day_prior)) +
      geom_density(fill = "lightgrey", color = "black") +
      geom_vline(xintercept = c(lower_bound, upper_bound), linetype = "dashed", color = "red") +
      geom_ribbon(data = data.frame(x = density_data$x, y = density_data$y),
                  aes(x = x, ymax = ifelse(x < lower_bound | x > upper_bound, y, 0), ymin = 0),
                  fill = "red", alpha = 0.5) +
      geom_ribbon(data = data.frame(x = density_data$x, y = density_data$y),
                  aes(x = x, ymax = ifelse(x < lower_bound | x > upper_bound, 0, y), ymin = 0),
                  fill = "lightgrey", alpha = 0.5) +
      labs(title = "Density Plot of Percentage Returns",
           x = "Percentage Returns",
           y = "Density") +
      theme_minimal()
    
    ggplotly(p1)
  })
  
  output$p2 <- renderPlotly({
    lower_bound <- -1*input$cutoff_input
    upper_bound <- input$cutoff_input
    p2<-ggplot(spy_data(), aes(x = as.Date(date), y = per_chg_from_day_prior)) +
      geom_rect(aes(xmin = as.Date(min(date)), xmax = as.Date(max(date)),
                    ymin = -.1, ymax = lower_bound),
                fill = "red", alpha = 0.1) +
      geom_rect(aes(xmin = as.Date(min(date)), xmax = as.Date(max(date)),
                    ymin = upper_bound, ymax = .1),
                fill = "red", alpha = 0.1) +
      geom_rect(aes(xmin = as.Date(min(date)), xmax = as.Date(max(date)),
                    ymin = lower_bound, ymax = upper_bound),
                fill = "gray", alpha = 0.1) +
      geom_line(color = "blue") +
      geom_hline(yintercept = c(lower_bound, upper_bound), linetype = "dashed", color = "red") +
      labs(title = "Percentage Return Over Time",
           x = "Date",
           y = "Percentage Return") +
      theme_minimal()
    ggplotly(p2)
    
  })
  
  output$pos_neg_table <- renderDataTable({
    lower_bound <- -1*input$cutoff_input
    upper_bound <- input$cutoff_input
    spy_data()%>%
      filter(per_chg_from_day_prior<=lower_bound | 
               per_chg_from_day_prior>=upper_bound)
  })
  
  output$p2_1 <- renderPlotly({
    split<-input$split_checkbox
    data<-spy_data2() 
    upper_limit<-input$max_days
    #browser()
    #Plot the number of days since last event (either negative or positive):
    p2_1<-data%>%
      ggplot(aes(x = num_since)) +
      geom_density(alpha = 0.7) +
      labs(title = "Distribution of Time Differences for Paired Abnormal Event",
           x = "Days Since Last Abnormal Event")+
      coord_cartesian(xlim=c(0,upper_limit))
    
    if(split){
      p2_1<-data %>%
        ggplot(aes(x = num_since,fill=type)) +
        geom_density(alpha = 0.7) +
        labs(title = "Distribution of Time Differences for Negative Events",
             x = "Days Since Last Negative Event")+
        coord_cartesian(xlim=c(0,upper_limit))
      
    }
    ggplotly(p2_1)
  })
  
  output$p2_2<-renderPlotly({
    split<-input$split_checkbox
    data<-spy_data2()
    upper_limit<-input$max_days
    #browser()
    p2_2 <- data %>%
      ggplot(aes(x = num_since, y = per_chg_from_day_prior)) +
      geom_smooth() +
    labs(title = "Relationship between Number of Days Since and Stock Price Change",
         x = "Number of Days Since",
         y = "Percentage Change from Previous Day",
         color = "Event Type")+
      scale_color_manual(values = c("num_obs_since_last_neg" = "red", "num_obs_since_last_pos" = "green"),
                         labels = c("num_obs_since_last_neg" = "Negative Abnormal Event",
                                    "num_obs_since_last_pos" = "Positive Abnormal Event"))+
      coord_cartesian(xlim=c(0,upper_limit))
    if(split){
      p2_2 <- data %>%
        ggplot(aes(x = num_since, y = per_chg_from_day_prior, color = type)) +
        geom_smooth() +
        labs(title = "Relationship between Number of Days Since and Stock Price Change",
             x = "Number of Days Since",
             y = "Percentage Change from Previous Day",
             color = "Event Type")+
        scale_color_manual(values = c("num_obs_since_last_neg" = "red", "num_obs_since_last_pos" = "green"),
                           labels = c("num_obs_since_last_neg" = "Negative Abnormal Event",
                                      "num_obs_since_last_pos" = "Positive Abnormal Event"))+
        coord_cartesian(xlim=c(0,upper_limit))
    }
    ggplotly(p2_2)
  })
  
  output$p2_3<-renderPlotly({
    data<-spy_data2() %>%
      filter(num_since<min(input$max_days,100))
    split<-input$split_checkbox
    
    p2_3 <- data%>%
      ggplot(aes(x = as.factor(num_since), y = per_chg_from_day_prior)) +
      geom_boxplot() +
      labs(title = "Boxplot of Stock Price Change Over Time",
           x = "Number of Days Since",
           y = "Percentage Change from Previous Day",
           color = "Event Type")+
      scale_color_manual(values = c("num_obs_since_last_neg" = "red", "num_obs_since_last_pos" = "green"),
                         labels = c("num_obs_since_last_neg" = "Negative Abnormal Event",
                                    "num_obs_since_last_pos" = "Positive Abnormal Event"))
    if(split){
      p2_3 <- data%>%
        ggplot(aes(x = as.factor(num_since), y = per_chg_from_day_prior, color = type)) +
        geom_boxplot() +
        labs(title = "Boxplot of Stock Price Change Over Time",
             x = "Number of Days Since",
             y = "Percentage Change from Previous Day",
             color = "Event Type")+
        scale_color_manual(values = c("num_obs_since_last_neg" = "red", "num_obs_since_last_pos" = "green"),
                           labels = c("num_obs_since_last_neg" = "Negative Abnormal Event",
                                      "num_obs_since_last_pos" = "Positive Abnormal Event"))
    }
    ggplotly(p2_3)
  })
  
  output$p3_1<-renderPlotly({
    split<-input$split_checkbox
    p3_1<-time_diff_data() %>%
      ggplot(aes(x = time_diff)) +
      geom_density(alpha = 0.7) +
      labs(title = "Distribution of Time Differences Between Unidirectional Abnormal Events",
           x = "Days Between Same Direction Abnormal Events")
    if(split){
      p3_1<-time_diff_data() %>%
        ggplot(aes(x = time_diff,fill=type)) +
        geom_density(alpha = 0.7) +
        labs(title = "Distribution of Time Differences Between Unidirectional Abnormal Events by Direction",
             x = "Days Between Unidirectional Abnormal Events")
    }
    ggplotly(p3_1)
  })
  
  output$p3_2<-renderPlotly({
    split<-input$split_checkbox
    p3_2 <- time_diff_data() %>%
      filter(time_diff > 0)%>%
      ggplot(aes(x = time_diff, y = per_chg_from_day_prior)) +
      geom_smooth() +
      labs(title = "Relationship between Abnormal Event Day Difference and Stock Price Change",
           x = "Number Of Days Between Abnormal Events",
           y = "Percentage Change from Previous Day",
           color = "Event Type")+
      scale_color_manual(values = c("Negative" = "red", "Positive" = "green"),
                         labels = c("Negative" = "Negative Abnormal Event",
                                    "Positive" = "Positive Abnormal Event"))+
      coord_cartesian(xlim=c(0,input$max_days))
    
    if(split){
      p3_2 <- time_diff_data() %>%
        filter(time_diff > 0)%>%
        ggplot(aes(x = time_diff, y = per_chg_from_day_prior, color = type)) +
        geom_smooth() +
        labs(title = "Relationship between Abnormal Event Day Difference and Stock Price Change",
             x = "Number Of Days Between Abnormal Events",
             y = "Percentage Change from Previous Day",
             color = "Event Type")+
        scale_color_manual(values = c("Negative" = "red", "Positive" = "green"),
                           labels = c("Negative" = "Negative Abnormal Event",
                                      "Positive" = "Positive Abnormal Event"))+
        coord_cartesian(xlim=c(0,input$max_days))
    }
    ggplotly(p3_2)
  })
  
  output$p3_3<-renderPlotly({
    split<-input$split_checkbox
    
    p3_3 <- time_diff_data() %>%
      filter(time_diff < min(100,input$max_days)) %>%
      filter(time_diff > 0)%>%
      ggplot(aes(x = as.factor(time_diff), y = per_chg_from_day_prior)) +
      geom_boxplot() +
      labs(title = "Boxplot of Daily Stock Price Change For Each Day Difference",
           x = "Number of Days Between Abnormal Event",
           y = "Percentage Change from Previous Day",
           color = "Event Type")+
      scale_color_manual(values = c("Negative" = "red", "Positive" = "green"),
                         labels = c("Negative" = "Negative Abnormal Event",
                                    "Positive" = "Positive Abnormal Event"))
    if(split){
      p3_3 <- time_diff_data() %>%
        filter(time_diff < min(100,input$max_days)) %>%
        filter(time_diff > 0)%>%
        ggplot(aes(x = as.factor(time_diff), y = per_chg_from_day_prior,color=type)) +
        geom_boxplot() +
        labs(title = "Boxplot of Daily Stock Price Change For Each Day Difference",
             x = "Number of Days Between Abnormal Event",
             y = "Percentage Change from Previous Day",
             color = "Event Type")+
        scale_color_manual(values = c("Negative" = "red", "Positive" = "green"),
                           labels = c("Negative" = "Negative Abnormal Event",
                                      "Positive" = "Positive Abnormal Event"))
    }
    ggplotly(p3_3)
  })
  
  output$p4_1<-renderPlotly({
    lag_n<-input$lag_slider
    log_scale<-input$log_checkbox
    split<-input$split_checkbox
    day_max <- ifelse(log_scale,log(input$max_days),input$max_days)
    
    data<-time_diff_lag()
    
    if(log_scale){
      data<-data%>%
        mutate(time_diff_before=log(time_diff_before),
               time_diff = log(time_diff))
    }
    
    p4_1<-data %>%
      ggplot(aes(x = time_diff_before, y = time_diff)) +
      geom_point() +
      geom_smooth() +
      coord_cartesian(xlim = c(1, day_max)) +
      labs(
        title = paste0("Relationship between",ifelse(log_scale," Log of "," "),"Time Difference (Lag t-", lag_n, ") and" ,ifelse(log_scale," Log of "," "),"Time Difference"),
        x = paste0(ifelse(log_scale," Log of "," "),"Time Difference Before (Lag t-",lag_n,")"),
        y = paste0(paste0(ifelse(log_scale," Log of "," "),"Time Difference Current (t)")),
        color = "Event Type"
      )
    
    if(split){
      p4_1<- data %>%
        ggplot(aes(x = time_diff_before, y = time_diff, color = type)) +
        geom_point() +
        geom_smooth() +
        labs(
          title = paste0("Relationship between",ifelse(log_scale," Log of "," "),"Time Difference (Lag t-", lag_n, ") and",ifelse(log_scale," Log of "," "),"Time Difference"),
          x = paste0(ifelse(log_scale," Log of "," "),"Time Difference Before (Lag t-",lag_n,")"),
          y = paste0(ifelse(log_scale," Log of "," "),"Time Difference Current (t)"),
          color = "Event Type"
        )
      
    }
    ggplotly(p4_1)
  })
  
  output$p4_2<-renderPlotly({
    split<-input$split_checkbox
    lag_n<-input$lag_slider
    log_scale<-input$log_checkbox
    data<-time_diff_lag()
    day_max <- ifelse(log_scale,log(input$max_days),input$max_days)
    if(log_scale){
      data<-data%>%
        mutate(time_diff_before=log(time_diff_before),
               time_diff = log(time_diff))
    }
    
    p4_2<-data %>%
      filter(time_diff_before < min(100,day_max))%>%
      ggplot(aes(x = as.factor(round(time_diff_before,1)), y = time_diff)) +
      geom_boxplot() +
      labs(
        title = paste0("Relationship between",ifelse(log_scale," Log of "," "),"Time Difference (Lag t-", lag_n, ") and",ifelse(log_scale," Log of "," ")," Time Difference"),
        x = paste0(ifelse(log_scale,"Log of ",""),"Time Difference Before (Lag t-",lag_n,")"),
        y = paste0(ifelse(log_scale,"Log of ",""),"Time Difference Current (t)"),
        color = "Event Type"
      )
    
    if(split){
      p4_2<-time_diff_lag() %>%
        filter(time_diff_before < min(100,day_max))%>%
        mutate(time_diff_before=log(time_diff_before),
               time_diff = log(time_diff))%>%
        ggplot(aes(x = as.factor(round(time_diff_before,1)), y = time_diff, color = type)) +
        geom_boxplot() +
        labs(
          title = paste0("Relationship between",ifelse(log_scale," Log of "," ")," Time Difference (Lag t-", lag_n, ") and ",ifelse(log_scale," Log of "," ")," Time Difference"),
          x = paste0(ifelse(log_scale," Log of "," "),"Time Difference Before (Lag t-",lag_n,")"),
          y = paste0(ifelse(log_scale," Log of "," "),"Time Difference Current (t)"),
          color = "Event Type"
        )
    }
    ggplotly(p4_2)
  })
}

shinyApp(ui, server)
